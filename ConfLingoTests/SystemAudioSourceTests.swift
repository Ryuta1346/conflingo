import AVFAudio
import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SystemAudioSourceTests {
    @Test func permissionInspectionAndUnpermittedStartNeverPrompt() async throws {
        let capture = StubSystemCapture()
        var requests = 0
        let source = SystemAudioSource(capture: capture, permissionStatus: { .unknown }, requestPermission: {
            requests += 1
            return false
        })
        #expect(source.permissionStatus == .unknown)
        #expect(source.origin == .systemAudio)
        let format = try makeFormat()
        await #expect(throws: AudioSourceError.permissionDenied) { try await source.start(targetFormat: format) }
        #expect(requests == 0)
        #expect(capture.starts == 0)
        #expect(await source.requestPermission() == false)
        #expect(requests == 1)
    }

    @Test func stopDuringStartWaitsForCaptureAndDiscardsLateSuccess() async throws {
        let capture = StubSystemCapture()
        capture.holdStart = true
        let source = makeSource(capture)
        let format = try makeFormat()
        let start = Task { try await source.start(targetFormat: format) }
        await capture.started.next()
        let stop = Task { try await source.stop() }
        // A second start must not create a second OS stream during either transition.
        await #expect(throws: AudioSourceError.alreadyRunning) { try await source.start(targetFormat: format) }
        capture.releaseStart.signal()
        try await stop.value
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(capture.stops == 1)
        #expect(source.state == .idle)
    }

    @Test func cancelledStartCleansUpLateOSSuccess() async throws {
        let capture = StubSystemCapture()
        capture.holdStart = true
        let source = makeSource(capture)
        let format = try makeFormat()
        let task = Task { try await source.start(targetFormat: format) }
        await capture.started.next()
        task.cancel()
        capture.releaseStart.signal()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(source.state == .idle)
        #expect(capture.stops == 1)
    }

    @Test func failedStartCleansUpAndRetryUsesNewStream() async throws {
        let capture = StubSystemCapture()
        capture.failStart = true
        let source = makeSource(capture)
        let format = try makeFormat()
        await #expect(throws: StubSystemCapture.Failure.start) { try await source.start(targetFormat: format) }
        #expect(source.state == .idle)
        #expect(capture.stops == 1)
        capture.failStart = false
        let stream = try await source.start(targetFormat: format)
        let producer = try #require(capture.continuation)
        producer.yield(try #require(AudioFrame(copying: makeBuffer([0.5], format: format))))
        try await source.stop()
        var values: [Float] = []
        for try await frame in stream { values += samples(frame.buffer) }
        #expect(values == [0.5])
        _ = try await source.start(targetFormat: format)
        if case .terminated = producer.yield(try #require(AudioFrame(copying: makeBuffer([1], format: format)))) {
        } else { Issue.record("Old stream accepted a frame") }
        try await source.stop()
    }

    @Test func concurrentStopsShareCompletionAndFailureCanBeRetried() async throws {
        let capture = StubSystemCapture()
        let source = makeSource(capture)
        _ = try await source.start(targetFormat: makeFormat())
        capture.holdStop = true
        capture.failStop = true
        let first = Task { try await source.stop() }
        await capture.stopping.next()
        let entered = TestSignal()
        let second = Task {
            entered.signal()
            try await source.stop()
        }
        await entered.next()
        capture.releaseStop.signal()
        await #expect(throws: StubSystemCapture.Failure.stop) { try await first.value }
        await #expect(throws: StubSystemCapture.Failure.stop) { try await second.value }
        #expect(capture.stops == 1)
        #expect(source.state == .stopping)
        capture.holdStop = false
        capture.failStop = false
        try await source.stop()
        #expect(source.state == .idle)
        #expect(capture.stops == 2)
    }

    @Test(arguments: [false, true])
    func concurrentStopCallerCanImmediatelyRestartOrRetry(failStop: Bool) async throws {
        for _ in 0..<100 {
            try await checkImmediateRestartOrRetry(failStop: failStop)
        }
    }

    private func checkImmediateRestartOrRetry(failStop: Bool) async throws {
        let capture = StubSystemCapture()
        let source = makeSource(capture)
        let format = try makeFormat()
        _ = try await source.start(targetFormat: format)
        capture.holdStop = true
        capture.failStop = failStop
        let first = Task { try await source.stop() }
        await capture.stopping.next()
        let entered = TestSignal()
        let second = Task {
            entered.signal()
            if failStop {
                do {
                    try await source.stop()
                    Issue.record("Stop unexpectedly succeeded")
                } catch {
                    #expect(error as? StubSystemCapture.Failure == .stop)
                }
                capture.failStop = false
                capture.holdStop = false
                try await source.stop()
                #expect(capture.stops == 2)
            } else {
                try await source.stop()
                #expect(capture.stops == 1)
            }
            #expect(source.state == .idle)
            _ = try await source.start(targetFormat: format)
        }
        await entered.next()
        capture.releaseStop.signal()
        let secondResult = await second.result
        if failStop {
            await #expect(throws: StubSystemCapture.Failure.stop) { try await first.value }
        } else {
            try await first.value
        }
        try secondResult.get()
        #expect(source.state == .running)
        #expect(capture.starts == 2)
        capture.holdStop = false
        try await source.stop()
        #expect(source.state == .idle)
    }

    @Test func runtimeFailureIsDeliveredToConsumer() async throws {
        let capture = StubSystemCapture()
        let source = makeSource(capture)
        let stream = try await source.start(targetFormat: makeFormat())
        capture.continuation?.finish(throwing: StubSystemCapture.Failure.runtime)
        await #expect(throws: StubSystemCapture.Failure.runtime) {
            for try await _ in stream {}
        }
        try await source.stop()
        #expect(source.state == .idle)
    }

    private func makeSource(_ capture: StubSystemCapture) -> SystemAudioSource {
        SystemAudioSource(capture: capture, permissionStatus: { .granted }, requestPermission: { true })
    }
}

@MainActor
final class TestSignal {
    private let pair = AsyncStream<Void>.makeStream()
    func signal() { pair.continuation.yield(()) }
    func next() async {
        var iterator = pair.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
}

@MainActor
final class StubSystemCapture: SystemAudioCapturing {
    enum Failure: Error { case start, stop, runtime }
    var starts = 0
    var stops = 0
    var holdStart = false
    var holdStop = false
    var failStart = false
    var failStop = false
    let started = TestSignal()
    let stopping = TestSignal()
    let releaseStart = TestSignal()
    let releaseStop = TestSignal()
    var continuation: AudioFrameStream.Continuation?

    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream {
        starts += 1
        let pair = AudioFrameStream.makeStream()
        continuation = pair.continuation
        started.signal()
        if holdStart { await releaseStart.next() }
        if failStart { throw Failure.start }
        return pair.stream
    }

    func stop() async throws {
        stops += 1
        continuation?.finish()
        stopping.signal()
        if holdStop { await releaseStop.next() }
        if failStop { throw Failure.stop }
        continuation = nil
    }
}
