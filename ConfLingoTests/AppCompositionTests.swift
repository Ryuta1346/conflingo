import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppCompositionTests {
    @Test(arguments: [
        ([String](), false, ConferenceNavigation.Destination.home),
        (["--ui-preview"], true, .live),
        (["--meeting-preview"], true, .meeting),
        (["--ui-preview", "--meeting-preview"], true, .meeting),
        (["--meeting-live-ai"], false, .home)
    ])
    func launchModeSelectsInitialScreen(arguments: [String], preview: Bool, destination: ConferenceNavigation.Destination) {
        let fixture = CompositionFixture(arguments: arguments)
        defer { fixture.cleanUp() }
        let app = fixture.app
        #expect(app.isPreview == preview)
        #expect(app.navigation.destination == destination)
        #expect(app.store.segments.isEmpty == !preview)
        #expect(app.meeting.phase == .idle)
        #expect(app.audioUse.owner == nil)
        #expect(app.defaults === fixture.defaults)
    }

    @Test func sharedServicesConnectConferenceAndMeeting() {
        let fixture = CompositionFixture()
        defer { fixture.cleanUp() }
        let app = fixture.app
        #expect(app.controller.activity === app.audioUse)
        #expect(app.meeting.controller.activity === app.audioUse)
        #expect(app.conferenceKnowledge.store === app.store)
        #expect(app.conferenceKnowledge.settings === app.meeting.llmSettings)
        app.store.phase = .listening
        let id = app.store.appendFinal("Shared transcript", startTime: 1)
        #expect(app.conferenceKnowledge.assistanceStore.finals.contains { $0.id == id })
        app.store.phase = .idle
    }

    @Test func previewMeetingOwnsAudioUntilStopped() async {
        let fixture = CompositionFixture()
        defer { fixture.cleanUp() }
        let app = fixture.app
        app.meeting.consentConfirmed = true
        await app.meeting.start()
        #expect(app.meeting.phase == .listening)
        #expect(app.audioUse.owner == .meeting)
        await app.controller.start(store: app.store, coordinator: app.coordinator, locale: Locale(identifier: "en-US"))
        #expect(app.store.phase == .idle)
        #expect(app.controller.lastError?.contains("使用中") == true)
        #expect(app.audioUse.owner == .meeting)
        await app.meeting.end()
        #expect(app.meeting.phase == .idle)
        #expect(app.audioUse.owner == nil)
    }

    @Test func viewRecreationKeepsSessionNavigationAndSettings() {
        let fixture = CompositionFixture()
        defer { fixture.cleanUp() }
        let app = fixture.app
        _ = ContentView(composition: app)
        app.meeting.name = "Retained meeting"
        let id = app.store.appendFinal("Retained caption", startTime: 5)
        app.navigation.request(.sessions, phase: .idle)
        app.profileStore.updateSelectedKeywords("SyntheticKeyword")
        app.meeting.microphoneTranslationLanguage = "de"
        _ = ContentView(composition: app)
        #expect(app.meeting.name == "Retained meeting")
        #expect(app.store.segments.contains { $0.id == id })
        #expect(app.navigation.destination == .sessions)
        #expect(KeywordProfileStore(defaults: fixture.defaults).selectedProfile.keywords == "SyntheticKeyword")
        #expect(fixture.defaults.string(forKey: "meetingMicrophoneTranslation") == "de")
    }

    @Test(arguments: [["--ui-preview"], ["--meeting-preview"]])
    func ordinaryPreviewUsesSyntheticAI(arguments: [String]) async throws {
        let fixture = CompositionFixture(arguments: arguments)
        defer { fixture.cleanUp() }
        let app = fixture.app
        #expect(!app.meeting.previewUsesLiveAI)
        #expect(app.conferenceKnowledge.client is PreviewInsightClient)
        #expect(!(app.meeting.credentials.store is KeychainAPIKeyStore))
        #expect(try await app.meeting.credentials.store.read() == nil)
        #expect(!app.meeting.ai.permitted)
    }

    @Test func explicitLivePreviewPreservesScenarioWithoutStartingWork() {
        let fixture = CompositionFixture(arguments: ["--meeting-preview", "--meeting-live-ai", "--meeting-state=review"])
        defer { fixture.cleanUp() }
        #expect(fixture.app.previewScenario == "review")
        #expect(fixture.app.meeting.previewUsesLiveAI)
        #expect(fixture.app.meeting.phase == .idle)
        #expect(fixture.app.meeting.insights.isEmpty)
        #expect(!fixture.app.meeting.ai.permitted)
    }
}

@MainActor
private struct CompositionFixture {
    let suite = "AppCompositionTests-\(UUID())"
    let defaults: UserDefaults
    let app: AppComposition

    init(arguments: [String] = ["--meeting-preview"]) {
        defaults = UserDefaults(suiteName: suite)!
        app = AppComposition(arguments: arguments, defaults: defaults)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}
