import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LongMeetingSummaryTests {
    @Test(arguments: [600, 601, 3_000])
    func shortUtterancesPreserveEveryIDBeyondOldLimit(count: Int) throws {
        let store = summaryStore(count: count)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals.reversed(), answerLanguage: .english)
        #expect(plan.requests.count == (count + 29) / 30)
        #expect(plan.requests.flatMap(\.events) == store.finals)
        #expect(plan.requests.allSatisfy { $0.omittedCount == 0 && $0.events.count <= 30 && $0.timeoutSeconds == 60 })
    }

    @Test func characterLimitCanReachHundredSectionsWithFewerUtterances() throws {
        let session = UUID()
        let events = (0..<100).map {
            insightEvent(session: session, text: String(repeating: "あ", count: 12_000), offset: Double($0))
        }
        let plan = try MeetingSummaryPlan(sessionID: session, events: events, answerLanguage: .japanese)
        #expect(plan.requests.count == 100)
        #expect(plan.requests.flatMap(\.events) == events)
        do {
            _ = try MeetingSummaryPlan(sessionID: session, events: events + [insightEvent(session: session, offset: 100)], answerLanguage: .japanese)
            Issue.record("The 101st section must be rejected")
        } catch MeetingSummaryPlan.PlanError.tooManySections {
            #expect(MeetingSummaryPlan.PlanError.tooManySections.localizedDescription.contains("100区間"))
        }
    }

    @Test func hundredSectionsGenerateOnceAndRoundTripWithEvidenceAndKnowledge() async throws {
        let store = summaryStore(count: 3_000)
        let ref = reference("design.md", snippet: "Synthetic supporting document")
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english,
                                         knowledgeBySection: Array(repeating: [ref], count: 100), knowledgeRevision: UUID())
        let client = LongSummaryClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        await summary.generate(plan, consent: false)
        #expect(client.requests.isEmpty)
        await summary.generate(plan, consent: true)
        let completed = try #require(summary.completed)
        #expect(summary.state == .complete)
        #expect(client.requests.map(\.id) == plan.requests.map(\.id))
        #expect(completed.sections.count == 100)
        #expect(completed.sections.flatMap(\.evidenceIDs) == store.finals.map(\.id))
        #expect(completed.sections.map(\.startOffset) == stride(from: 0, to: 3_000, by: 30).map(Double.init))
        #expect(completed.sections.allSatisfy { $0.knowledgeReferences == [ref] })
        let snapshot = SessionSnapshot.meeting(MeetingExportSnapshot(title: "Long synthetic meeting", startedAt: nil,
            microphoneLocale: "en", systemLocale: "ja", sessionID: store.sessionID,
            events: store.finals, candidates: [], summary: completed), [])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try await SessionFiles(directory: root).save(snapshot)
        let restored = try await SessionFiles(directory: root).load(store.sessionID)
        #expect(restored == saved)
        #expect(restored.version == 1)
        #expect(restored.snapshot == snapshot)
        let markdown = restored.snapshot.markdown
        #expect(markdown.components(separatedBy: "](#utterance-").count - 1 == 3_000)
        #expect(markdown.contains("Synthetic summary 100"))
        #expect(markdown.contains(ref.snippet))
    }

    @Test(arguments: [false, true])
    func stoppingAtSectionTwentyOneKeepsOldCompletionAndSendsNoLaterSection(cancel: Bool) async throws {
        let store = summaryStore(count: 631)
        let client = LongSummaryClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english)
        await summary.generate(plan, consent: true)
        let completed = try #require(summary.completed)
        client.requests = []
        let gate = TestGate()
        if cancel { client.gate = gate } else { client.failAt = 21 }
        let operation = Task { await summary.generate(plan, consent: true) }
        if cancel {
            await gate.entered.next()
            #expect(client.requests.count == 21)
            await summary.generate(plan, consent: true)
            summary.cancel()
            gate.release()
        }
        await operation.value
        #expect(client.requests.count == 21)
        #expect(summary.draft.count == 20)
        #expect(summary.completed == completed)
        #expect(summary.state == (cancel ? .interrupted : .failed(.offline)))
        let snapshot = MeetingExportSnapshot(title: "Retained", startedAt: nil, microphoneLocale: "en", systemLocale: "ja",
            sessionID: store.sessionID, events: store.finals, candidates: [], summary: summary.completed)
        #expect(snapshot.summary?.sections.count == 22)
    }

    @Test func longKnowledgePlanSearchesEverySectionAndRejectsChangedDocuments() async throws {
        let client = LongSummaryClient()
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client)
        await meeting.knowledge.add(data: Data("refundPayment handles refunds".utf8), filename: "design.md")
        for index in 0..<601 {
            meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "refundPayment discussion \(index)", offset: Double(index)))
        }
        await meeting.end()
        let plan = try await meeting.summaryPlan(includingKnowledge: true)
        #expect(plan.requests.count == 21)
        #expect(plan.requests.allSatisfy { !$0.knowledge.isEmpty && $0.knowledge.count <= 5
            && $0.knowledge.reduce(0) { $0 + $1.snippet.count } <= 6_000 })
        #expect(!meeting.knowledge.permitted)
        await meeting.generateSummary(plan, consent: false)
        #expect(client.requests.isEmpty)
        await meeting.knowledge.remove(try #require(meeting.knowledge.documents.first?.id))
        #expect(!meeting.isSummaryPlanCurrent(plan))
        await meeting.generateSummary(plan, consent: true)
        #expect(client.requests.isEmpty)
    }

    @Test func exceedingLimitDoesNotSendOrDiscardExistingSummaryAndTranscript() async throws {
        let client = LongSummaryClient()
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client)
        meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "Original", offset: 0))
        await meeting.end()
        await meeting.generateSummary(try meeting.summaryPlan(), consent: true)
        let completed = try #require(meeting.summary.completed)
        client.requests = []
        for index in 1..<3_001 {
            meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "More speech \(index)", offset: Double(index)))
        }
        do {
            _ = try meeting.summaryPlan()
            Issue.record("Over-limit planning must fail before sending")
        } catch MeetingSummaryPlan.PlanError.tooManySections {
            #expect(client.requests.isEmpty)
        }
        #expect(meeting.summary.completed == completed)
        #expect(meeting.exportSnapshot?.events.count == 3_001)
    }

}

@MainActor
private final class LongSummaryClient: InsightClient {
    var requests: [InsightRequest] = []
    var failAt: Int?
    var gate: TestGate?

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        if requests.count == failAt { throw InsightFailure.offline }
        if requests.count == 21, let gate { await gate.wait() }
        return InsightResult(kind: .answerSuggestion, text: "Synthetic summary \(requests.count)", evidenceIDs: request.events.map(\.id),
            knowledgeIDs: request.knowledge.map(\.id), supplement: request.knowledge.isEmpty ? nil : "Synthetic supplement")
    }
}
