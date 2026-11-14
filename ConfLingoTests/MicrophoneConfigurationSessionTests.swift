import Foundation
import Observation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MicrophoneConfigurationSessionTests {
    @Test func conferenceStopsShowsFailureAndCanRestart() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let source = MicrophoneAudioSource(
            capture: AudioCaptureService(engine: engine, notificationCenter: center), permissionStatus: { .granted })
        let speech = StreamOnlySpeech(source: source)
        let activity = AudioInputUse()
        let controller = SessionController(audioSource: source, speechService: speech, activity: activity)
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(store.phase == .listening)
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        try await waitForConfigurationStop { store.phase == .idle }
        #expect(store.phase == .idle)
        #expect(source.state == .idle)
        #expect(activity.owner == nil)
        #expect(controller.lastError?.contains("もう一度開始") == true)
        // 失敗時にも入力を残さず終了し、次の開始を独立に検証する。
        await controller.stop(store: store, coordinator: coordinator)
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(store.phase == .listening)
        #expect(controller.lastError == nil)
        await controller.stop(store: store, coordinator: coordinator)
    }

    @Test func meetingConfigurationFailureStopsBothInputsAndReleasesOwnership() async throws {
        let engine = try StubMicrophoneEngine()
        let center = NotificationCenter()
        let microphone = MicrophoneAudioSource(
            capture: AudioCaptureService(engine: engine, notificationCenter: center), permissionStatus: { .granted })
        let systemCapture = StubSystemCapture()
        let system = SystemAudioSource(capture: systemCapture, permissionStatus: { .granted })
        let activity = AudioInputUse()
        let controller = DualTranscriptionController(
            microphone: microphone, systemAudio: system,
            microphoneSpeech: StreamOnlySpeech(source: microphone), systemSpeech: StreamOnlySpeech(source: system),
            activity: activity, prepareModel: { $0 })
        await controller.start()
        #expect(controller.phase == .listening)
        #expect(microphone.state == .running)
        #expect(system.state == .running)
        center.post(name: .AVAudioEngineConfigurationChange, object: engine.notificationObject)
        try await waitForConfigurationStop { controller.phase == .idle }
        #expect(controller.phase == .idle)
        #expect(microphone.state == .idle)
        #expect(system.state == .idle)
        #expect(activity.owner == nil)
        #expect(controller.lastError?.contains("もう一度開始") == true)
        await controller.stop()
        await controller.start()
        #expect(controller.phase == .listening)
        #expect(controller.lastError == nil)
        await controller.stop()
    }
}

/// SpeechAnalyzerの消費だけを代替。capture/source/入力sequence/controllerは製品コードを使用。
@MainActor
private final class StreamOnlySpeech: SpeechTranscribing {
    let service: SpeechTranscriptionService
    var consumer: Task<Void, Never>?
    init(source: any AudioSource) { service = SpeechTranscriptionService(audioSource: source) }

    func start(locale: Locale, contextKeywords: [String], fastResults: Bool,
               onInputStarted: @escaping @MainActor () -> Void,
               receive: @escaping @MainActor (SpeechResult) async throws -> Void,
               onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        let input = try await service.startAudioInput(targetFormat: makeFormat(), onFailure: onFailure)
        onInputStarted()
        consumer = Task {
            do { for try await _ in input {} } catch { /* 入力sequenceが失敗を通知する。 */ }
        }
    }

    func stopInput() async throws { try await service.stopInput() }
    func finishRecognition() async throws { await consumer?.value; consumer = nil }
    func cancelRecognition() async { consumer?.cancel(); await consumer?.value; consumer = nil }
    func stop() async throws { try await stopInput(); try await finishRecognition() }
}

@MainActor
private func waitForConfigurationStop(_ stopped: @escaping @MainActor @Sendable () -> Bool) async throws {
    for await isStopped in Observations({ stopped() }) {
        try Task.checkCancellation()
        if isStopped { return }
    }
    throw CancellationError()
}
