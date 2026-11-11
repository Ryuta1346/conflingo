import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AutomaticKnowledgeTests {
    @Test func permissionIsIndependentAndEventTextFindsReferencesBeyondFirstQuery() async throws {
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("PilotService supports pilot rollout.".utf8), filename: "architecture.md")
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        var time = 100.0
        let ai = InsightCoordinator(store: store, client: client, now: { time }, knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        knowledge.setPermission(true)
        #expect(!ai.automaticKnowledgeEnabled)
        await ai.receive(insightEvent(session: store.sessionID, text: "PilotService?"))?.value
        #expect(client.requests.last?.knowledge.isEmpty == true)
        knowledge.setPermission(false)
        ai.setAutomaticKnowledge(true)
        time += 12
        let event = insightEvent(session: store.sessionID, text: String(repeating: "z ", count: 1_100) + "PilotService rollout?")
        await ai.receive(event)?.value
        let request = try #require(client.requests.last)
        #expect(request.trigger == .automatic)
        #expect(request.knowledge.count == 1)
        #expect(ai.insights.last?.knowledgeReferences == request.knowledge)
        #expect(!knowledge.permitted)
        ai.setPermission(false, after: 0)
        #expect(!ai.automaticKnowledgeEnabled)
        ai.setAutomaticKnowledge(true)
        #expect(!ai.automaticKnowledgeEnabled)
    }

    @Test(arguments: ["automatic", "knowledge", "ai", "suspend", "reset", "remove", "session"], [false, true])
    func cancellationRejectsLateResults(action: String, generating: Bool) async throws {
        let gate = TestGate()
        let knowledge = KnowledgeStore(lookup: { _, _ in
            if !generating { await gate.wait() }
            return [reference()]
        })
        await knowledge.add(data: Data("fixture".utf8), filename: "fixture.md")
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        if generating { client.gate = gate }
        let ai = configured(store, client, knowledge)
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await gate.entered.next()
        switch action {
        case "automatic": ai.setAutomatic(false, after: 0)
        case "knowledge": ai.setAutomaticKnowledge(false); ai.setAutomaticKnowledge(true)
        case "ai": ai.setPermission(false, after: 0)
        case "suspend": ai.suspend()
        case "reset": ai.reset()
        case "remove": await knowledge.remove(try #require(knowledge.documents.first?.id))
        default: ai.reset(); store.reset(sessionID: UUID()); ai.resume(); ai.setPermission(true, after: 0)
        }
        gate.release()
        await operation.value
        #expect(client.requests.count == (generating ? 1 : 0))
        #expect(!ai.insights.contains { $0.status == .complete })
    }

    @Test func manualPreemptsLookupAndLateLookupCannotCancelManual() async throws {
        let lookupGate = TestGate()
        let knowledge = KnowledgeStore(lookup: { _, _ in await lookupGate.wait(); return [reference()] })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let ai = configured(store, client, knowledge)
        let automatic = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await lookupGate.entered.next()
        #expect(ai.canAsk)
        let manualGate = TestGate()
        client.gate = manualGate
        let manual = Task { await ai.ask("Manual question") }
        await manualGate.entered.next()
        lookupGate.release()
        await automatic.value
        #expect(ai.state == .sending)
        manualGate.release()
        await manual.value
        #expect(client.requests.map(\.trigger) == [.manual])
        #expect(ai.insights.last?.status == .complete)
    }

    @Test func lookupReservesRateLimitAndDoesNotQueueEvents() async throws {
        let gate = TestGate()
        var lookups = 0
        let knowledge = KnowledgeStore(lookup: { _, _ in
            lookups += 1
            if lookups == 1 { await gate.wait() }
            return []
        })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        var time = 100.0
        let ai = configured(store, client, knowledge, now: { time })
        let first = insightEvent(session: store.sessionID, text: "First question?")
        let operation = try #require(ai.receive(first))
        await gate.entered.next()
        #expect(ai.receive(insightEvent(session: store.sessionID, text: "Busy?")) == nil)
        ai.setAutomaticKnowledge(false)
        gate.release()
        await operation.value
        ai.setAutomaticKnowledge(true)
        #expect(ai.receive(first) == nil)
        #expect(ai.receive(insightEvent(session: store.sessionID, text: "Too soon?")) == nil)
        time = 112
        await ai.receive(insightEvent(session: store.sessionID, text: "Second question?"))?.value
        time = 125
        #expect(ai.receive(insightEvent(session: store.sessionID, text: "Third question?")) == nil)
        #expect(lookups == 2)
        #expect(client.requests.count == 1)
        #expect(client.requests.first?.knowledge.isEmpty == true)
    }

    @Test func lookupFailureStopsAutomaticWithoutSending() async {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let knowledge = KnowledgeStore(lookup: { _, _ in throw KnowledgeFailure.search })
        let ai = configured(store, client, knowledge)
        await ai.receive(insightEvent(session: store.sessionID))?.value
        #expect(client.requests.isEmpty)
        #expect(ai.state == .failed(.knowledge))
        #expect(!ai.automaticEnabled)
    }

    @Test func timeoutIncludesLookupAndRejectsLateResults() async throws {
        let gate = TestGate()
        let knowledge = KnowledgeStore(lookup: { _, _ in await gate.wait(); return [reference()] })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let ai = configured(store, client, knowledge, timeout: .milliseconds(30))
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await gate.entered.next()
        await gate.cancelled.next()
        #expect(ai.state == .failed(.timeout))
        gate.release()
        await operation.value
        #expect(client.requests.isEmpty)
        #expect(!ai.automaticEnabled)
    }

    @Test func manualPermissionChangeDoesNotCancelAutomaticAndAutoRevocationDoes() async throws {
        let knowledge = KnowledgeStore(lookup: { _, _ in [reference()] })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let gate = TestGate()
        client.gate = gate
        let ai = configured(store, client, knowledge)
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await gate.entered.next()
        knowledge.setPermission(true)
        knowledge.setPermission(false)
        #expect(ai.state == .sending)
        ai.setAutomaticKnowledge(false)
        await gate.cancelled.next()
        gate.release()
        await operation.value
        #expect(ai.insights.last?.status == .interrupted)
        #expect(ai.automaticEnabled)
    }

    @Test func automaticPreviewUsesRepositoryCitationsAndEndsWithoutChangingSummaryPermission() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse(), scenario: "repository-automatic")
        await MeetingPreview.prepare(meeting, scenario: "repository-automatic")
        #expect(meeting.page == .live)
        #expect(meeting.ai.automaticKnowledgeEnabled)
        #expect(!meeting.knowledge.permitted)
        let card = try #require(meeting.insights.last)
        #expect(card.status == .complete)
        #expect(card.knowledgeReferences.first?.source != nil)
        #expect(!card.evidenceIDs.isEmpty)
        await meeting.end()
        let plan = try meeting.summaryPlan()
        #expect(plan.requests.allSatisfy { $0.knowledge.isEmpty })
        meeting.setAutomaticKnowledgeAllowed(false)
        meeting.setAutomaticKnowledgeAllowed(true)
        #expect(!meeting.ai.automaticKnowledgeEnabled)
    }

    @Test func repositoryAndOrdinarySourcesShareBoundsAndPreserveSnapshotLanguage() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        for number in 0..<7 { try fixture.write("Sources/Refund\(number).swift", "func refundPayment\(number)() {}") }
        let knowledge = KnowledgeStore()
        let scan = try await RepositoryImporter.scan(fixture.root)
        await knowledge.importRepository(scan, selected: Set(scan.eligible.map(\.path)))
        await knowledge.add(data: Data("refund payment 設計上の予定".utf8), filename: "design.md")
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let ai = configured(store, client, knowledge)
        ai.answerLanguage = .english
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID, text: "refund payment?")))
        ai.answerLanguage = .japanese
        await operation.value
        let request = try #require(client.requests.first)
        #expect(request.answerLanguage == .english)
        #expect(request.knowledge.count == 5)
        #expect(request.knowledge.reduce(0) { $0 + $1.snippet.count } <= 6_000)
        #expect(request.knowledge.contains { $0.source != nil })
        #expect(Set(request.knowledge.map(\.id)).count == 5)
        await knowledge.removeRepository()
        #expect(ai.insights.last?.knowledgeReferences == request.knowledge)
    }

    @Test func autoRevocationDoesNotCancelManualAndScheduledRevocationNeverSearches() async throws {
        var searches = 0
        let knowledge = KnowledgeStore(lookup: { _, _ in searches += 1; return [reference()] })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let ai = configured(store, client, knowledge)
        let automatic = try #require(ai.receive(insightEvent(session: store.sessionID)))
        ai.setAutomaticKnowledge(false)
        await automatic.value
        #expect(searches == 0)
        #expect(client.requests.isEmpty)
        ai.setAutomaticKnowledge(true)
        knowledge.setPermission(true)
        let gate = TestGate()
        client.gate = gate
        let manual = Task { await ai.ask("manual?") }
        await gate.entered.next()
        ai.setAutomaticKnowledge(false)
        #expect(ai.state == .sending)
        gate.release()
        await manual.value
        #expect(ai.insights.last?.status == .complete)
        #expect(knowledge.permitted)
    }

    @Test func subscriptionOverflowCancelsLookupWithoutBlockingEventDelivery() async throws {
        let gate = TestGate()
        let knowledge = KnowledgeStore(lookup: { _, _ in await gate.wait(); return [reference()] })
        let store = MeetingSessionStore(sessionID: UUID())
        let client = AutomaticKnowledgeClient()
        let ai = configured(store, client, knowledge)
        let hub = TranscriptEventHub(finalCapacity: 1)
        await ai.attach(to: hub)
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await gate.entered.next()
        try await hub.publishAutomaticTestBurst((0..<5).map { insightEvent(session: store.sessionID, text: "plain \($0)") })
        await gate.cancelled.next()
        #expect(ai.state == .failed(.queueOverflow))
        gate.release()
        await operation.value
        #expect(client.requests.isEmpty)
        #expect(!ai.automaticEnabled)
        ai.suspend()
    }

    @Test func automaticCandidateKeepsSpeechAndRepositoryEvidenceInMarkdown() async throws {
        var ref = reference("Review.swift", snippet: "func reviewStatus() {}")
        ref.source = RepositorySource(snapshotID: UUID(), name: "Product", path: "Sources/Review.swift", contentHash: String(repeating: "a", count: 64))
        let knowledge = KnowledgeStore(lookup: { _, _ in [ref] })
        let store = MeetingSessionStore(sessionID: UUID())
        let event = insightEvent(session: store.sessionID, text: "Who will reviewStatus? I will follow up.")
        store.receive(event)
        let client = AutomaticKnowledgeClient()
        client.kind = .actionCandidate
        let ai = configured(store, client, knowledge)
        await ai.receive(event)?.value
        let candidate = try #require(ai.candidates.items.first)
        #expect(candidate.review == .unreviewed)
        let output = MeetingExportSnapshot(title: "Synthetic", startedAt: nil, microphoneLocale: "en", systemLocale: "en",
                                          sessionID: store.sessionID, events: store.finals, candidates: ai.candidates.items, summary: nil).markdown
        #expect(output.contains("未確認の候補"))
        #expect(output.contains("Product/Sources/Review.swift"))
        #expect(output.contains(#"> func reviewStatus\(\) \{\}"#))
        #expect(output.contains("utterance-\(event.id.uuidString.lowercased())"))
    }

    private func configured(_ store: MeetingSessionStore, _ client: AutomaticKnowledgeClient, _ knowledge: KnowledgeStore,
                            now: @escaping () -> TimeInterval = { 100 }, timeout: Duration = .seconds(30)) -> InsightCoordinator {
        let ai = InsightCoordinator(store: store, client: client, now: now, timeout: timeout, knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        ai.setAutomaticKnowledge(true)
        return ai
    }
}

@MainActor
private final class AutomaticKnowledgeClient: InsightClient {
    var requests: [InsightRequest] = []
    var gate: TestGate?
    var kind: MeetingInsight.Kind = .answerSuggestion
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        await gate?.wait()
        return InsightResult(kind: kind, text: String((request.events.last?.text ?? request.question).prefix(1_000)),
                             evidenceIDs: request.events.map(\.id), knowledgeIDs: request.knowledge.map(\.id))
    }
}

private extension TranscriptEventHub {
    func publishAutomaticTestBurst(_ events: [TranscriptEvent]) throws {
        for event in events { try publish(event) }
    }
}
