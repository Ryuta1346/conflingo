// Validation-only app entry point. Copy over ConfLingoApp.swift in a temporary project.
// No microphone, system audio, SpeechAnalyzer, Keychain or network operations.
import AVFAudio
import SwiftUI

@main
struct StatusValidationApp: App {
    @State private var fixture = StatusFixture()

    var body: some Scene {
        Window("Transcript Status Validation", id: "status-validation") {
            VStack {
                HStack {
                    Button("Run synthetic sequence") { Task { await fixture.run() } }
                        .disabled(fixture.running)
                    Text("\(fixture.stage) | finals=\(fixture.controller.store.finals.count) partials=\(fixture.controller.store.partials.count)")
                }
                DualTranscriptionProbeView(controller: fixture.controller)
            }
            .padding()
        }
        .defaultSize(width: 1000, height: 900)
    }
}

@MainActor @Observable
final class StatusFixture {
    let microphone = StatusSpeech()
    let system = StatusSpeech()
    let controller: DualTranscriptionController
    var running = false
    var stage = "ready"

    init() {
        controller = DualTranscriptionController(
            microphone: StatusSource(origin: .microphone),
            systemAudio: StatusSource(origin: .systemAudio),
            microphoneSpeech: microphone, systemSpeech: system,
            prepareModel: { $0 }
        )
    }

    func run() async {
        running = true
        stage = "running"
        await controller.start(microphoneLocale: Locale(identifier: "ja-JP"), systemLocale: Locale(identifier: "en-US"))
        do {
            for index in 0..<9 {
                let text = "System sentence \(index + 1): 200 ms target 100 ms."
                try await system.emit(text, time: Double(index), final: false)
                try await Task.sleep(for: .milliseconds(400))
                if index == 4 {
                    try await microphone.emit("マイクの確認。200ミリ秒、目標100ミリ秒。", time: 9, final: false)
                }
                try await system.emit(text, time: Double(index), final: true)
                try await Task.sleep(for: .milliseconds(400))
            }
            microphone.finalOnStop = "マイクの確認。200ミリ秒、目標100ミリ秒。"
            await controller.stop()
            stage = "stopped"
        } catch {
            await controller.stop()
            stage = "failed"
        }
        running = false
    }
}

@MainActor
final class StatusSource: AudioSource {
    let origin: AudioOrigin
    let permissionStatus = AudioPermissionStatus.granted
    let state = AudioSourceState.idle
    init(origin: AudioOrigin) { self.origin = origin }
    func requestPermission() async -> Bool { true }
    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream {
        fatalError("Validation fixture must never start audio")
    }
    func stop() async throws {}
}

@MainActor
final class StatusSpeech: SpeechTranscribing {
    var receive: (@MainActor (SpeechResult) async throws -> Void)?
    var finalOnStop: String?

    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        self.receive = receive
        onInputStarted()
    }
    func emit(_ text: String, time: Double, final: Bool) async throws {
        try await receive?(SpeechResult(text: text, isFinal: final, startTime: time, endTime: time + 1))
    }
    func stopInput() async throws {}
    func finishRecognition() async throws {
        if let finalOnStop { try await emit(finalOnStop, time: 9, final: true) }
    }
    func cancelRecognition() async {}
    func stop() async throws { try await finishRecognition() }
}
