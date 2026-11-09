import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    private let isPreview: Bool
    private let isMeetingPreview: Bool
    private let defaults: UserDefaults
    @State private var audioUse: AudioInputUse
    @State private var systemAudioProbe: SystemAudioProbeController
    @State private var dualTranscription: DualTranscriptionController
    @State private var meeting: MeetingWorkspace
    @State private var floatingPanel: MeetingFloatingPanel
    @State private var previewPrepared = false

    init() {
        #if DEBUG
        isMeetingPreview = ProcessInfo.processInfo.arguments.contains("--meeting-preview")
        isPreview = isMeetingPreview || ProcessInfo.processInfo.arguments.contains("--ui-preview")
        defaults = isMeetingPreview ? MeetingPreview.defaults : isPreview ? ConferencePreview.defaults : .standard
        #else
        isPreview = false
        isMeetingPreview = false
        defaults = .standard
        #endif
        _alwaysOnTop = AppStorage(wrappedValue: false, "alwaysOnTop", store: defaults)
        let activity = AudioInputUse()
        _audioUse = State(initialValue: activity)
        _systemAudioProbe = State(initialValue: SystemAudioProbeController(activity: activity))
        _dualTranscription = State(initialValue: DualTranscriptionController(activity: activity))
        #if DEBUG
        _meeting = State(initialValue: isPreview
                         ? MeetingPreview.make(activity: activity, scenario: MeetingPreview.scenario,
                                               liveAI: MeetingPreview.liveAIEnabled(arguments: ProcessInfo.processInfo.arguments))
                         : MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting)))
        #else
        _meeting = State(initialValue: MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting)))
        #endif
        _floatingPanel = State(initialValue: MeetingFloatingPanel(defaults: defaults))
    }

    var body: some Scene {
        Window(isPreview ? "ConfLingo — UI Preview" : "ConfLingo", id: "main") {
            ContentView(activity: audioUse, preview: isPreview, defaults: defaults,
                        meeting: meeting, floatingPanel: floatingPanel, meetingPreview: isMeetingPreview)
                .frame(minWidth: 640, minHeight: 520)
                .task {
                    #if DEBUG
                    if isMeetingPreview && !previewPrepared {
                        previewPrepared = true
                        await MeetingPreview.prepare(meeting, scenario: MeetingPreview.scenario)
                    }
                    #endif
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowLevel(alwaysOnTop ? .floating : .normal)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Meetingの小窓を表示") { floatingPanel.show(meeting: meeting) }
            }
        }

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
