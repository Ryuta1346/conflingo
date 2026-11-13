import AVFAudio
import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AudioCaptureConfigurationTests {
    @Test func backgroundNotificationStopsInputAndReleaseRemovesActiveCapture() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        var capture: AudioCaptureService? = AudioCaptureService(engine: engine, notificationCenter: center)
        let stream = try #require(capture).start(targetFormat: makeFormat())
        let identity = engine.identity
        await Task.detached {
            center.post(name: .AVAudioEngineConfigurationChange, object: identity)
        }.value
        await settleConfigurationTasks()
        #expect(engine.stops == 1)
        capture?.stop()
        await #expect(throws: AudioCaptureError.configurationChanged) { for try await _ in stream {} }
        _ = try #require(capture).start(targetFormat: makeFormat())
        capture = nil
        #expect(engine.stops == 2)
        center.post(name: .AVAudioEngineConfigurationChange, object: identity)
        await settleConfigurationTasks()
        #expect(engine.stops == 2)
    }

    @Test func configurationChangeStopsInputWithActionableError() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        let stream = try capture.start(targetFormat: makeFormat())
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        await settleConfigurationTasks()
        #expect(engine.stops == 1)
        // Redでも消費が無期限に待たないよう、判定後に通常停止する。
        capture.stop()
        var failure: (any Error)?
        do { for try await _ in stream {} } catch { failure = error }
        #expect(failure?.localizedDescription.contains("マイク") == true)
        #expect(failure?.localizedDescription.contains("開始") == true)
        #expect(engine.stops == 1)
    }

    @Test func unrelatedAndInactiveNotificationsDoNotOpenOrStopInput() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        capture.stop()
        await settleConfigurationTasks()
        #expect(engine.formatReads == 0)
        #expect(engine.stops == 0)
        let stream = try capture.start(targetFormat: makeFormat())
        center.post(name: .AVAudioEngineConfigurationChange, object: NSObject())
        await settleConfigurationTasks()
        #expect(engine.stops == 0)
        capture.stop()
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        await settleConfigurationTasks()
        for try await _ in stream {}
        #expect(engine.stops == 1)
    }

    @Test func queuedOldNotificationDoesNotStopRestartedInput() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        let first = try capture.start(targetFormat: makeFormat())
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        capture.stop()
        engine.inputFormat = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let second = try capture.start(targetFormat: engine.inputFormat)
        await settleConfigurationTasks()
        #expect(engine.stops == 1)
        #expect(engine.tapFormats.map(\.sampleRate) == [16_000, 48_000])
        engine.receive?(try makeBuffer([0.25], format: engine.inputFormat))
        capture.stop()
        for try await _ in first {}
        var values: [Float] = []
        for try await frame in second { values += samples(frame.buffer) }
        #expect(values == [0.25])
    }

    @Test func repeatedNotificationsStopOnceAndNextRunCanCapture() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        _ = try capture.start(targetFormat: makeFormat())
        for _ in 0..<3 {
            center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        }
        await settleConfigurationTasks()
        #expect(engine.stops == 1)
        capture.stop()
        let stream = try capture.start(targetFormat: makeFormat())
        engine.receive?(try makeBuffer([0.5], format: makeFormat()))
        capture.stop()
        var values: [Float] = []
        for try await frame in stream { values += samples(frame.buffer) }
        #expect(values == [0.5])
        #expect(engine.stops == 2)
    }

    @Test func failedStartRemovesTapAndIgnoresQueuedNotificationOnRetry() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        engine.beforeStart = { center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject) }
        engine.failStart = true
        #expect(throws: StubMicrophoneEngine.Failure.start) { try capture.start(targetFormat: makeFormat()) }
        engine.beforeStart = nil
        engine.failStart = false
        let stream = try capture.start(targetFormat: makeFormat())
        await settleConfigurationTasks()
        #expect(engine.stops == 1)
        capture.stop()
        for try await _ in stream {}
        #expect(engine.stops == 2)
    }
}

@MainActor
final class StubMicrophoneEngine: MicrophoneCaptureEngine {
    enum Failure: Error { case start }
    let identity = CaptureNotificationIdentity()
    var notificationObject: AnyObject { identity }
    private var format: AVAudioFormat
    var inputFormat: AVAudioFormat {
        get { formatReads += 1; return format }
        set { format = newValue }
    }
    var formatReads = 0
    var tapFormats: [AVAudioFormat] = []
    var stops = 0
    var failStart = false
    var beforeStart: (() -> Void)?
    var receive: (@Sendable (AVAudioPCMBuffer) -> Void)?

    init() throws { format = try makeFormat() }
    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        tapFormats.append(format)
        self.receive = receive
    }
    func start() throws {
        beforeStart?()
        if failStart { throw Failure.start }
    }
    func stop() { stops += 1; receive = nil }
}

/// 通知のobject識別にだけ使う、可変状態を持たないオブジェクト。
final class CaptureNotificationIdentity: NSObject, @unchecked Sendable {}

@MainActor
func settleConfigurationTasks() async {
    for _ in 0..<50 { await Task.yield() }
}
