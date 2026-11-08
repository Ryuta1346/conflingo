import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    private let isPreview: Bool
    private let defaults: UserDefaults
    @State private var audioUse: AudioInputUse
    @State private var systemAudioProbe: SystemAudioProbeController
    @State private var dualTranscription: DualTranscriptionController

    init() {
        #if DEBUG
        isPreview = ProcessInfo.processInfo.arguments.contains("--ui-preview")
        defaults = isPreview ? ConferencePreview.defaults : .standard
        #else
        isPreview = false
        defaults = .standard
        #endif
        _alwaysOnTop = AppStorage(wrappedValue: false, "alwaysOnTop", store: defaults)
        let activity = AudioInputUse()
        _audioUse = State(initialValue: activity)
        _systemAudioProbe = State(initialValue: SystemAudioProbeController(activity: activity))
        _dualTranscription = State(initialValue: DualTranscriptionController(activity: activity))
    }

    var body: some Scene {
        Window(isPreview ? "ConfLingo — UI Preview" : "ConfLingo", id: "main") {
            ContentView(activity: audioUse, preview: isPreview, defaults: defaults)
                .frame(minWidth: 640, minHeight: 520)
        }
        .defaultSize(width: 1180, height: 780)
        .windowLevel(alwaysOnTop ? .floating : .normal)

        Window("システム音声の確認", id: "system-audio-probe") {
            SystemAudioProbeView(controller: systemAudioProbe)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("2入力文字起こしの確認", id: "dual-transcription-probe") {
            DualTranscriptionProbeView(controller: dualTranscription)
        }
        .defaultSize(width: 800, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
