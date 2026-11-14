import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AssistanceLifecycleTests {
    @Test func sharedSettingsRevokeEveryWorkspaceWithoutOverwritingSubscribers() throws {
        let settings = conferenceTestSettings()
        let first = MeetingWorkspace(controller: DualFixture().controller(), insightClient: KnowledgeClient(), llmSettings: settings)
        let second = MeetingWorkspace(controller: DualFixture().controller(), insightClient: KnowledgeClient(), llmSettings: settings)
        let conference = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: settings, client: KnowledgeClient())
        first.setAIAllowed(true)
        second.setAIAllowed(true)
        conference.setAssistancePermission(true)
        first.research.setPermission(true)
        second.research.setPermission(true)
        conference.research.setPermission(true)
        var connection = settings.selected
        connection.model = "changed-model"
        try settings.save(connection)
        #expect(!first.ai.permitted)
        #expect(!second.ai.permitted)
        #expect(!conference.assistance.permitted)
        #expect(!first.research.permitted && !second.research.permitted && !conference.research.permitted)
    }

    @Test func replacingConferenceDoesNotRetainOrDisconnectRemainingWorkspace() {
        let store = SessionStore()
        let settings = conferenceTestSettings()
        var first: ConferenceKnowledgeWorkspace? = ConferenceKnowledgeWorkspace(store: store, settings: settings, client: KnowledgeClient())
        weak var released = first
        let second = ConferenceKnowledgeWorkspace(store: store, settings: settings, client: KnowledgeClient())
        store.appendFinal("First utterance.")
        #expect(first?.assistanceStore.finals.count == 1)
        #expect(second.assistanceStore.finals.count == 1)
        first = nil
        #expect(released == nil)
        store.appendFinal("Second utterance.")
        second.synchronizeSpeech()
        second.synchronizeSpeech()
        #expect(second.assistanceStore.finals.count == 2)
        store.reset()
        #expect(second.assistanceStore.sessionID == store.sessionID)
        #expect(second.assistanceStore.finals.isEmpty)
    }
}

extension AssistanceLifecycleTests {
    @Test func additionalFinalSubscriberPreservesTranslationAndRejectsDuplicateOrOldSessionEvents() throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: KnowledgeClient(),
            llmSettings: conferenceTestSettings(), translationClientFactory: { _, _ in FakeMeetingTranslator() })
        meeting.mode = .translation
        var delivered: [UUID] = []
        let subscription = meeting.store.finalEvents.observe { delivered.append($0.id) }
        defer { subscription.cancel() }
        let event = insightEvent(session: meeting.store.sessionID, text: "Hello", offset: 1)
        #expect(meeting.store.receive(event))
        #expect(!meeting.store.receive(event))
        #expect(delivered == [event.id])
        #expect(meeting.translations.entries[event.id] != nil)
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(!meeting.store.receive(event))
        #expect(meeting.translations.entries.isEmpty)
        #expect(delivered == [event.id])
    }

    @Test func additionalKnowledgeSubscriberPreservesPermissionResetAndCancellation() async throws {
        let client = KnowledgeClient()
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client,
            llmSettings: conferenceTestSettings())
        await meeting.knowledge.add(data: Data("price 100".utf8), filename: "price.md")
        meeting.setAIAllowed(true)
        meeting.setAutomaticAI(true)
        meeting.setKnowledgeAllowed(true)
        meeting.setAutomaticKnowledgeAllowed(true)
        meeting.research.setPermission(true)
        var contentNotifications = 0
        var invalidations = 0
        let content = meeting.knowledge.contentChanges.observe { contentNotifications += 1 }
        let invalidation = meeting.knowledge.invalidations.observe { invalidations += 1 }
        defer { content.cancel(); invalidation.cancel() }
        let gate = TestGate()
        client.gate = gate
        let pending = Task { await meeting.askAssistance("price?") }
        await gate.entered.next()
        await meeting.knowledge.remove(try #require(meeting.knowledge.documents.first?.id))
        #expect(!meeting.knowledge.permitted)
        #expect(!meeting.ai.automaticKnowledgeEnabled)
        #expect(!meeting.research.permitted)
        gate.release()
        await pending.value
        #expect(meeting.insights.allSatisfy { $0.status != .complete })
        #expect(contentNotifications == 1 && invalidations == 1)
    }

    @Test(arguments: [false, true])
    func stoppedRequestsCannotOverwriteAnswersAfterResume(conference: Bool) async {
        let client = KnowledgeClient()
        let settings = conferenceTestSettings()
        let support = SessionAssistance(store: MeetingSessionStore(sessionID: UUID()), settings: settings, client: client)
        let conferenceWorkspace = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: settings, client: client)
        let active = conference ? conferenceWorkspace.support : support
        active.resume()
        active.setPermission(true, after: 0)
        let gate = TestGate()
        client.gate = gate
        let pending = Task { await active.ai.ask("old question") }
        await gate.entered.next()
        active.suspend()
        client.gate = nil
        active.resume()
        await active.ai.ask("new question")
        let completed = active.ai.insights.filter { $0.status == .complete }
        #expect(completed.count == 1)
        gate.release()
        await pending.value
        #expect(active.ai.insights.filter { $0.status == .complete } == completed)
        #expect(client.requests.map(\.question) == ["old question", "new question"])
    }

    @Test func restartReplacesPhaseSubscriptionAndPreservesExternalObserver() async {
        let fixture = DualFixture()
        let dual = fixture.controller(owner: .conference)
        let controller = SessionController(dualController: dual)
        let first = SessionStore()
        let second = SessionStore()
        let translation = TranslationCoordinator()
        var phases: [SessionPhase] = []
        let subscription = dual.phaseChanges.observe { phases.append($0) }
        defer { subscription.cancel() }
        await controller.start(store: first, coordinator: translation, locale: Locale(identifier: "en"))
        await controller.stop(store: first, coordinator: translation)
        var oldPhases: [SessionPhase] = []
        let oldSubscription = first.phaseChanges.observe { oldPhases.append($0) }
        defer { oldSubscription.cancel() }
        await controller.start(store: second, coordinator: translation, locale: Locale(identifier: "en"))
        #expect(first.phase == .idle)
        #expect(second.phase == .listening)
        await controller.stop(store: second, coordinator: translation)
        #expect(oldPhases.isEmpty)
        #expect(phases.filter { $0 == .listening }.count == 2)
        #expect(second.phase == .idle)
    }
}
