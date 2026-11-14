import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @State private var composition: AppComposition
    @State private var previewPrepared = false

    init() {
        let composition = AppComposition(arguments: ProcessInfo.processInfo.arguments)
        _composition = State(initialValue: composition)
        _alwaysOnTop = AppStorage(wrappedValue: false, "alwaysOnTop", store: composition.defaults)
    }

    var body: some Scene {
        Window(composition.isPreview ? "ConfLingo — UI Preview" : "ConfLingo", id: "main") {
            ContentView(composition: composition)
                .frame(minWidth: 640, minHeight: 520)
                .task {
                    #if DEBUG
                    if composition.isMeetingPreview && !previewPrepared {
                        previewPrepared = true
                        await MeetingPreview.prepare(composition.meeting, scenario: composition.previewScenario)
                    }
                    #endif
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowLevel(alwaysOnTop ? .floating : .normal)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Meetingの小窓を表示") { composition.floatingPanel.show(meeting: composition.meeting) }
            }
        }

        #if DEBUG
        Window("システム音声の確認", id: "system-audio-probe") {
            SystemAudioProbeView(controller: composition.systemAudioProbe)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("2入力文字起こしの確認", id: "dual-transcription-probe") {
            DualTranscriptionProbeView(controller: composition.dualTranscription)
        }
        .defaultSize(width: 800, height: 600)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}
