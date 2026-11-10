import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingSummaryTests {
    @Test(arguments: [(30.0, 15.0, 30.0), (30.0, nil, 30.0), (nil, nil, 10.0)] as [(Double?, Double?, Double)])
    func sectionRangeCoversOverlappingUtterancesAndUnknownEnds(longEnd: Double?, shortEnd: Double?, expectedEnd: Double) async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        for (origin, start, end) in [(AudioOrigin.microphone, 0.0, longEnd), (.systemAudio, 10.0, shortEnd)] {
            store.receive(TranscriptEvent(id: UUID(), sessionID: store.sessionID, origin: origin, languageCode: "en-US",
                                          startOffset: start, endOffset: end, text: "Synthetic overlap", isFinal: true,
                                          revision: 1, sourceStartTime: start))
        }
        let summary = MeetingSummaryCoordinator(store: store, client: FakeInsightClient())
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english)
        await summary.generate(plan, consent: true)
        let completed = try #require(summary.completed)
        #expect(completed.sections.first?.startOffset == 0)
        #expect(completed.sections.first?.endOffset == expectedEnd)
        let snapshot = MeetingExportSnapshot(title: "Overlap", startedAt: nil, microphoneLocale: "en", systemLocale: "en",
                                              sessionID: store.sessionID, events: store.finals, candidates: [], summary: completed)
        #expect(snapshot.markdown.contains(expectedEnd == 30 ? "00:00:00–00:00:30" : "00:00:00–00:00:10"))
    }

    @Test func planPreservesEntireTimelineAndEnforcesBoundaries() throws {
        let session = UUID()
        let events = (0..<61).map { insightEvent(session: session, text: "line \($0)", offset: Double($0)) }
        let plan = try MeetingSummaryPlan(sessionID: session, events: events.reversed(), answerLanguage: .english)
        #expect(plan.requests.map { $0.events.count } == [30, 30, 1])
        #expect(plan.requests.flatMap(\.events).map(\.id) == events.map(\.id))
        #expect(plan.requests.allSatisfy { $0.omittedCount == 0 && $0.answerLanguage == .english })
        let large = insightEvent(session: session, text: String(repeating: "あ", count: 12_000))
        let bounded = try MeetingSummaryPlan(sessionID: session, events: [large, events[1]], answerLanguage: .japanese)
        #expect(bounded.requests.count == 2)
        #expect(throws: (any Error).self) {
            try MeetingSummaryPlan(sessionID: session, events: [insightEvent(session: session, text: String(repeating: "a", count: 12_001))], answerLanguage: .japanese)
        }
        #expect(throws: (any Error).self) {
            try MeetingSummaryPlan(sessionID: session, events: (0..<601).map { insightEvent(session: session, offset: Double($0)) }, answerLanguage: .japanese)
        }
        #expect(throws: (any Error).self) {
            try MeetingSummaryPlan(sessionID: session, events: [], answerLanguage: .japanese)
        }
    }

    @Test func explicitConsentIsRequiredAndSuccessfulSummaryCoversAllChunks() async throws {
        let store = summaryStore(count: 31)
        let client = FakeInsightClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese)
        await summary.generate(plan, consent: false)
        #expect(client.requests.isEmpty)
        await summary.generate(plan, consent: true)
        #expect(summary.state == .complete)
        #expect(summary.completed?.sections.count == 2)
        #expect(summary.completed?.sections.flatMap(\.evidenceIDs) == store.finals.map(\.id))
        #expect(client.requests.count == 2)
    }

    @Test func cancelRejectsLateResultsAndSendsNoLaterChunk() async throws {
        let store = summaryStore(count: 31)
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese)
        let operation = Task { await summary.generate(plan, consent: true) }
        await gate.entered.next()
        await summary.generate(plan, consent: true)
        summary.cancel()
        gate.release()
        await operation.value
        #expect(client.requests.count == 1)
        #expect(summary.completed == nil)
        #expect(summary.state == .interrupted)
    }

    @Test func failedRegenerationKeepsLastCompletedSummary() async throws {
        let store = summaryStore(count: 1)
        let client = FakeInsightClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese)
        await summary.generate(plan, consent: true)
        let completed = summary.completed
        client.failure = InsightFailure.offline
        await summary.generate(plan, consent: true)
        #expect(summary.state == .failed(.offline))
        #expect(summary.completed == completed)
    }

    @Test func invalidEvidenceAndPartialFailureCannotProduceCompletedSummary() async throws {
        let store = summaryStore(count: 31)
        let client = SummaryResponseClient()
        client.failAt = 2
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese)
        await summary.generate(plan, consent: true)
        #expect(summary.completed == nil)
        #expect(summary.draft.count == 1)
        #expect(summary.state == .failed(.invalidResponse))
        client.failAt = nil
        client.invalidEvidence = true
        await summary.generate(plan, consent: true)
        #expect(summary.completed == nil)
        #expect(summary.draft.isEmpty)
    }

    @Test func deadlineAndChangedSessionRejectLateResults() async throws {
        let store = summaryStore(count: 1)
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let summary = MeetingSummaryCoordinator(store: store, client: client, timeout: .milliseconds(10))
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese)
        let operation = Task { await summary.generate(plan, consent: true) }
        await gate.entered.next()
        await gate.cancelled.next()
        #expect(summary.state == .failed(.timeout))
        gate.release()
        await operation.value
        #expect(summary.completed == nil)
        store.reset(sessionID: UUID())
        await summary.generate(plan, consent: true)
        #expect(client.requests.count == 1)
    }
}

@MainActor
func summaryStore(count: Int) -> MeetingSessionStore {
    let store = MeetingSessionStore(sessionID: UUID())
    for index in 0..<count {
        store.receive(insightEvent(session: store.sessionID, text: "Synthetic line \(index)", offset: Double(index)))
    }
    return store
}

@MainActor
private final class SummaryResponseClient: InsightClient {
    var calls = 0
    var failAt: Int?
    var invalidEvidence = false
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        calls += 1
        if calls == failAt { throw InsightFailure.invalidResponse }
        return InsightResult(kind: .answerSuggestion, text: "Synthetic summary", evidenceIDs: invalidEvidence ? [UUID()] : request.events.map(\.id))
    }
}
