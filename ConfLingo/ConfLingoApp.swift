import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @State private var audioUse: AudioInputUse
    @State private var systemAudioProbe: SystemAudioProbeController
    @State private var dualTranscription: DualTranscriptionController

    init() {
        let activity = AudioInputUse()
        _audioUse = State(initialValue: activity)
        _systemAudioProbe = State(initialValue: SystemAudioProbeController(activity: activity))
        _dualTranscription = State(initialValue: DualTranscriptionController(activity: activity))
    }

    var body: some Scene {
        Window("ConfLingo", id: "main") {
            ContentView(activity: audioUse)
        }
        .defaultSize(width: 720, height: 560)
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
