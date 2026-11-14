import Foundation

@MainActor
final class AppComposition {
    let defaults: UserDefaults
    let isPreview: Bool
    let isMeetingPreview: Bool
    let audioUse: AudioInputUse
    let sessions: SessionsLibrary
    let library: KnowledgeLibrary
    let meeting: MeetingWorkspace
    let conferenceKnowledge: ConferenceKnowledgeWorkspace
    let floatingPanel: MeetingFloatingPanel
    let store: SessionStore
    let coordinator: TranslationCoordinator
    let availability: ModelAvailabilityService
    let controller: SessionController
    let navigation: ConferenceNavigation
    let profileStore: KeywordProfileStore
    #if DEBUG
    let previewScenario: String
    let systemAudioProbe: SystemAudioProbeController
    let dualTranscription: DualTranscriptionController
    #endif

    init(arguments: [String] = [], defaults: UserDefaults? = nil) {
        #if DEBUG
        isMeetingPreview = arguments.contains("--meeting-preview")
        isPreview = isMeetingPreview || arguments.contains("--ui-preview")
        previewScenario = arguments.first { $0.hasPrefix("--meeting-state=") }?
            .replacingOccurrences(of: "--meeting-state=", with: "") ?? "setup"
        let settings = defaults ?? (isMeetingPreview ? MeetingPreview.defaults : isPreview ? ConferencePreview.defaults : .standard)
        #else
        isPreview = false
        isMeetingPreview = false
        let settings = defaults ?? .standard
        #endif
        self.defaults = settings
        let activity = AudioInputUse()
        audioUse = activity
        sessions = SessionsLibrary.make(preview: isPreview)
        library = KnowledgeLibrary.make(preview: isPreview)
        let session = SessionStore()
        store = session
        #if DEBUG
        systemAudioProbe = SystemAudioProbeController(activity: activity)
        dualTranscription = DualTranscriptionController(activity: activity)
        if isPreview { ConferencePreview.populate(session) }
        let workspace = isPreview
            ? MeetingPreview.make(activity: activity, scenario: previewScenario,
                                  liveAI: MeetingPreview.liveAIEnabled(arguments: arguments), defaults: settings)
            : MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting), defaults: settings)
        conferenceKnowledge = ConferenceKnowledgeWorkspace(store: session, settings: workspace.llmSettings,
            client: isPreview ? PreviewInsightClient() : nil)
        #else
        let workspace = MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting), defaults: settings)
        conferenceKnowledge = ConferenceKnowledgeWorkspace(store: session, settings: workspace.llmSettings)
        #endif
        meeting = workspace
        floatingPanel = MeetingFloatingPanel(defaults: settings)
        coordinator = TranslationCoordinator()
        availability = ModelAvailabilityService()
        controller = SessionController(activity: activity)
        #if DEBUG
        navigation = ConferenceNavigation(destination: isMeetingPreview ? .meeting : isPreview ? .live : .home)
        #else
        navigation = ConferenceNavigation()
        #endif
        profileStore = KeywordProfileStore(defaults: settings)
    }
}
