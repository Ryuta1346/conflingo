import AVFAudio
import Foundation
import Speech
import Testing
@testable import ConfLingo

struct SpeechTranscriptionServiceTests {
    @Test @MainActor func normalStopAndCancelledConsumptionDoNotReportFailure() async throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let service = SpeechTranscriptionService(audioSource: source)
        var failures = 0
        let normal = try await service.startAudioInput(targetFormat: makeFormat(), onFailure: { _ in failures += 1 })
        try capture.emit([0.25, 0.5], format: makeFormat())
        try await service.stop()
        var values: [Float] = []
        for try await frame in normal { values += samples(frame.buffer) }
        #expect(values == [0.25, 0.5])
        #expect(failures == 0)

        let cancelled = try await service.startAudioInput(targetFormat: makeFormat(), onFailure: { _ in failures += 1 })
        let consumer = Task {
            do { for try await _ in cancelled {} } catch { }
        }
        consumer.cancel()
        capture.continuation?.finish(throwing: AudioCaptureError.configurationChanged)
        await consumer.value
        try await service.stop()
        #expect(failures == 0)
        #expect(source.state == .idle)
    }

    @Test @MainActor func microphoneConfigurationFailureNotifiesSessionWithoutRecognitionResults() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let capture = AudioCaptureService(engine: engine, notificationCenter: center)
        let source = MicrophoneAudioSource(capture: capture, permissionStatus: { .granted })
        let service = SpeechTranscriptionService(audioSource: source)
        var failures: [String] = []
        let input = try await service.startAudioInput(targetFormat: makeFormat(), onFailure: {
            failures.append($0.localizedDescription)
        })
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        await settleConfigurationTasks()
        try await source.stop()
        await #expect(throws: AudioCaptureError.configurationChanged) {
            for try await _ in input {}
        }
        #expect(failures.count == 1)
        #expect(failures.first?.contains("もう一度開始") == true)
        #expect(source.state == .idle)
    }

    @Test @MainActor func runtimeInputErrorReachesAnalyzerSequenceConsumer() async throws {
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        let service = SpeechTranscriptionService(audioSource: source)
        let input = try await service.startAudioInput(targetFormat: makeFormat())
        capture.continuation?.finish(throwing: StubSystemCapture.Failure.runtime)
        await #expect(throws: StubSystemCapture.Failure.runtime) {
            for try await _ in input {}
        }
        try await service.stop()
        #expect(source.state == .idle)
    }

    @Test @MainActor func audioSourceFeedsAnalyzerInputsInOrderAndStopEndsInput() async throws {
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let service = SpeechTranscriptionService(audioSource: source)
        let format = try makeFormat()
        let inputs = try await service.startAudioInput(targetFormat: format)
        try capture.emit([0.25, -0.5], format: format)
        try capture.emit([0.75], format: format)
        try await service.stop()
        var values: [[Float]] = []
        for try await input in inputs {
            #expect(input.buffer.format == format)
            values.append(samples(input.buffer))
        }
        #expect(values == [[0.25, -0.5], [0.75]])
        #expect(capture.format == format)
        #expect(source.state == .idle)
        #expect(capture.stops == 1)
    }

    @Test @MainActor func sourceFailureReachesCallerAndServiceCanStartAgain() async throws {
        let capture = StubAudioCapture()
        capture.failStart = true
        let source = StubMicrophonePermission().source(capture: capture)
        let service = SpeechTranscriptionService(audioSource: source)
        let format = try makeFormat()
        await #expect(throws: StubAudioCapture.Failure.start) { try await service.startAudioInput(targetFormat: format) }
        #expect(source.state == .idle)
        capture.failStart = false
        let inputs = try await service.startAudioInput(targetFormat: format)
        try capture.emit([0.5], format: format)
        try await service.stop()
        var values: [Float] = []
        for try await input in inputs { values += samples(input.buffer) }
        #expect(values == [0.5])
    }

    @Test func reportingOptionsDefaultPrioritizesAccuracy() {
        #expect(
            SpeechTranscriptionService.reportingOptions(fastResults: false)
                == [.volatileResults]
        )
    }

    @Test func reportingOptionsFastResultsPrioritizesLatency() {
        #expect(
            SpeechTranscriptionService.reportingOptions(fastResults: true)
                == [.volatileResults, .fastResults]
        )
    }
}
