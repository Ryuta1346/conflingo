import AVFAudio
import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AudioSourceTests {
    @Test func alreadyCancelledRequestDoesNotPromptOrOpenDevice() async throws {
        let permission = StubMicrophonePermission(status: .undetermined)
        let capture = StubAudioCapture()
        let source = permission.source(capture: capture)
        let format = try makeFormat()
        let task = Task {
            let allowed = await source.requestPermission()
            #expect(!allowed)
            #expect(throws: CancellationError.self) { try source.start(targetFormat: format) }
        }
        task.cancel()
        await task.value
        #expect(permission.requests == 0)
        #expect(capture.starts == 0)
        #expect(source.state == .idle)
    }

    @Test(arguments: [AudioPermissionStatus.granted, .denied, .undetermined, .unknown])
    func inspectingPermissionDoesNotRequestIt(status: AudioPermissionStatus) {
        let permission = StubMicrophonePermission(status: status)
        let source = permission.source(capture: StubAudioCapture())
        #expect(source.origin == .microphone)
        #expect(source.permissionStatus == status)
        #expect(source.state == .idle)
        #expect(permission.requests == 0)
    }

    @Test(arguments: [AudioPermissionStatus.denied, .undetermined, .unknown])
    func unpermittedStartDoesNotOpenDevice(status: AudioPermissionStatus) throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission(status: status).source(capture: capture)
        let format = try makeFormat()
        #expect(throws: AudioSourceError.permissionDenied) { try source.start(targetFormat: format) }
        #expect(capture.starts == 0)
        #expect(source.state == .idle)
    }

    @Test(arguments: [true, false])
    func permissionDecisionIsReflectedInInputAccess(granted: Bool) async throws {
        let permission = StubMicrophonePermission(status: .undetermined)
        permission.decision = granted
        let capture = StubAudioCapture()
        let source = permission.source(capture: capture)
        let allowed = await source.requestPermission()
        #expect(allowed == granted)
        #expect(permission.requests == 1)
        #expect(source.permissionStatus == (granted ? .granted : .denied))
        let format = try makeFormat()
        if granted {
            _ = try source.start(targetFormat: format)
            source.stop()
            #expect(capture.starts == 1)
        } else {
            #expect(throws: AudioSourceError.permissionDenied) { try source.start(targetFormat: format) }
            #expect(capture.starts == 0)
        }
    }

    @Test(arguments: [AudioPermissionStatus.granted, .denied, .unknown])
    func resolvedPermissionDoesNotPromptAgain(status: AudioPermissionStatus) async {
        let permission = StubMicrophonePermission(status: status)
        let source = permission.source(capture: StubAudioCapture())
        let allowed = await source.requestPermission()
        #expect(allowed == (status == .granted))
        #expect(permission.requests == 0)
    }

    @Test func overlappingPermissionRequestsSharePromptAndCancellationDoesNotGrantAccess() async {
        let permission = StubMicrophonePermission(status: .undetermined)
        permission.hold = true
        let source = permission.source(capture: StubAudioCapture())
        let first = Task { await source.requestPermission() }
        var prompted = permission.prompted.stream.makeAsyncIterator()
        _ = await prompted.next()
        let secondEntered = AsyncStream<Void>.makeStream()
        let second = Task {
            secondEntered.continuation.yield(())
            return await source.requestPermission()
        }
        var entered = secondEntered.stream.makeAsyncIterator()
        _ = await entered.next()
        first.cancel()
        permission.release.continuation.yield(())
        let firstAllowed = await first.value
        let secondAllowed = await second.value
        #expect(!firstAllowed)
        #expect(secondAllowed)
        #expect(permission.requests == 1)
    }

    @Test func startForwardsFormatAndStopFinishesFramesOnce() async throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let format = try makeFormat()
        source.stop()
        #expect(capture.stops == 0)
        let stream = try source.start(targetFormat: format)
        #expect(source.state == .running)
        #expect(capture.format == format)
        try capture.emit([0.25, -0.5], format: format)
        try capture.emit([0.75], format: format)
        source.stop()
        source.stop()
        var values: [[Float]] = []
        for await frame in stream { values.append(samples(frame.buffer)) }
        #expect(values == [[0.25, -0.5], [0.75]])
        #expect(capture.stops == 1)
        #expect(source.state == .idle)
    }

    @Test func secondStartKeepsOriginalInputAlive() async throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let format = try makeFormat()
        let stream = try source.start(targetFormat: format)
        #expect(throws: AudioSourceError.alreadyRunning) { try source.start(targetFormat: format) }
        #expect(capture.starts == 1)
        #expect(capture.stops == 0)
        #expect(source.state == .running)
        try capture.emit([0.5], format: format)
        source.stop()
        var values: [Float] = []
        for await frame in stream { values += samples(frame.buffer) }
        #expect(values == [0.5])
    }

    @Test func failedStartClosesPartialStreamAndCanRetry() async throws {
        let capture = StubAudioCapture()
        capture.failStart = true
        let source = StubMicrophonePermission().source(capture: capture)
        let format = try makeFormat()
        #expect(throws: StubAudioCapture.Failure.start) { try source.start(targetFormat: format) }
        #expect(capture.stops == 1)
        #expect(source.state == .idle)
        var failed = try #require(capture.stream).makeAsyncIterator()
        let end = await failed.next()
        #expect(end == nil)
        capture.failStart = false
        let retried = try source.start(targetFormat: format)
        try capture.emit([1], format: format)
        source.stop()
        var values: [Float] = []
        for await frame in retried { values += samples(frame.buffer) }
        #expect(values == [1])
        #expect(source.state == .idle)
    }

    @Test func restartUsesNewStreamAndRejectsOldProducer() async throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let format = try makeFormat()
        let first = try source.start(targetFormat: format)
        let oldProducer = try #require(capture.continuation)
        source.stop()
        let second = try source.start(targetFormat: format)
        let stale = try #require(AudioFrame(copying: makeBuffer([0.1], format: format)))
        if case .terminated = oldProducer.yield(stale) {} else { Issue.record("Old producer is still active") }
        try capture.emit([0.9], format: format)
        source.stop()
        var oldCount = 0
        for await _ in first { oldCount += 1 }
        var values: [Float] = []
        for await frame in second { values += samples(frame.buffer) }
        #expect(oldCount == 0)
        #expect(values == [0.9])
    }

    @Test func frameOwnsSamplesWhenDeviceReusesItsBuffer() throws {
        let format = try makeFormat()
        let original = try makeBuffer([0.25, -0.5], format: format)
        let frame = try #require(AudioFrame(copying: original))
        original.floatChannelData?[0][0] = 1
        original.frameLength = 1
        #expect(frame.buffer !== original)
        #expect(frame.buffer.format == format)
        #expect(samples(frame.buffer) == [0.25, -0.5])
    }
}

@MainActor
final class StubMicrophonePermission {
    var status: AudioPermissionStatus
    var decision = true
    var requests = 0
    var hold = false
    let prompted = AsyncStream<Void>.makeStream()
    let release = AsyncStream<Void>.makeStream()

    init(status: AudioPermissionStatus = .granted) { self.status = status }

    func source(capture: StubAudioCapture) -> MicrophoneAudioSource {
        MicrophoneAudioSource(
            capture: capture,
            permissionStatus: { self.status },
            requestPermission: {
                self.requests += 1
                self.prompted.continuation.yield(())
                if self.hold {
                    for await _ in self.release.stream { break }
                }
                self.status = self.decision ? .granted : .denied
                return self.decision
            }
        )
    }
}

@MainActor
final class StubAudioCapture: AudioCapturing {
    enum Failure: Error { case start }
    var starts = 0
    var stops = 0
    var failStart = false
    var format: AVAudioFormat?
    var stream: AsyncStream<AudioFrame>?
    var continuation: AsyncStream<AudioFrame>.Continuation?

    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<AudioFrame> {
        starts += 1
        format = targetFormat
        let pair = AsyncStream<AudioFrame>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        if failStart { throw Failure.start }
        return pair.stream
    }

    func emit(_ values: [Float], format: AVAudioFormat) throws {
        let frame = try #require(AudioFrame(copying: makeBuffer(values, format: format)))
        continuation?.yield(frame)
    }

    func stop() {
        stops += 1
        continuation?.finish()
        continuation = nil
    }
}

func makeFormat() throws -> AVAudioFormat {
    try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
}

func makeBuffer(_ values: [Float], format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count)))
    buffer.frameLength = AVAudioFrameCount(values.count)
    let channel = try #require(buffer.floatChannelData?[0])
    for (index, value) in values.enumerated() { channel[index] = value }
    return buffer
}

func samples(_ buffer: AVAudioPCMBuffer) -> [Float] {
    guard let channel = buffer.floatChannelData?[0] else { return [] }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}
