import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @State private var systemAudioProbe = SystemAudioProbeController()

    var body: some Scene {
        Window("ConfLingo", id: "main") {
            ContentView()
        }
        .defaultSize(width: 720, height: 560)
        .windowLevel(alwaysOnTop ? .floating : .normal)

        Window("システム音声の確認", id: "system-audio-probe") {
            SystemAudioProbeView(controller: systemAudioProbe)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}
