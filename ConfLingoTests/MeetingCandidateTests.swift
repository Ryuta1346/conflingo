import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct MeetingCandidateTests {
    @Test func confirmationRejectionAndRestorationPreserveEvidence() throws {
        let transcript = MeetingSessionStore(sessionID: UUID())
        let event = insightEvent(session: transcript.sessionID)
        transcript.receive(event)
        let store = MeetingCandidateStore(transcript: transcript)
        let card = MeetingInsight(kind: .decisionCandidate, text: "Release after review", priority: 1, evidenceIDs: [event.id])
        store.receive(card, sessionID: transcript.sessionID)
        #expect(store.items.first?.review == .unreviewed)
        store.setReview(.confirmed, for: card.id)
        store.receive(card, sessionID: transcript.sessionID)
        #expect(store.items.count == 1)
        #expect(store.items.first?.review == .confirmed)
        store.setReview(.rejected, for: card.id)
        #expect(store.items.first?.review == .rejected)
        store.setReview(.unreviewed, for: card.id)
        #expect(store.items.first?.evidenceIDs == [event.id])
        #expect(store.items.first?.review == .unreviewed)
    }

    @Test func incompleteInvalidAndForeignCandidatesCannotBeConfirmed() {
        let transcript = MeetingSessionStore(sessionID: UUID())
        let store = MeetingCandidateStore(transcript: transcript)
        for status in [MeetingInsight.Status.generating, .interrupted] {
            store.receive(MeetingInsight(kind: .actionCandidate, text: "Task", priority: 1, evidenceIDs: [], status: status), sessionID: transcript.sessionID)
        }
        store.receive(MeetingInsight(kind: .decisionCandidate, text: "Foreign", priority: 1, evidenceIDs: []), sessionID: UUID())
        #expect(store.items.isEmpty)
        for evidence in [[], [UUID()]] {
            let card = MeetingInsight(kind: .actionCandidate, text: "Check owner", priority: 1, evidenceIDs: evidence)
            store.receive(card, sessionID: transcript.sessionID)
            store.setReview(.confirmed, for: card.id)
            #expect(store.items.last?.review == .unreviewed)
            store.setReview(.rejected, for: card.id)
            #expect(store.items.last?.review == .rejected)
        }
        let event = insightEvent(session: transcript.sessionID)
        transcript.receive(event)
        let invalid = MeetingInsight(kind: .decisionCandidate, text: "Invalid", priority: 1, evidenceIDs: [event.id], hasInvalidEvidence: true)
        store.receive(invalid, sessionID: transcript.sessionID)
        store.setReview(.confirmed, for: invalid.id)
        #expect(store.items.last?.review == .unreviewed)
        transcript.reset(sessionID: UUID())
        store.setReview(.confirmed, for: invalid.id)
        #expect(!store.canConfirm(invalid.id))
    }

    @Test func realAICompletionRetainsCandidatesPastCardLimitAndResetClearsThem() async throws {
        let transcript = MeetingSessionStore(sessionID: UUID())
        transcript.receive(insightEvent(session: transcript.sessionID))
        let client = CandidateClient()
        let ai = InsightCoordinator(store: transcript, client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        await ai.ask("Decision?")
        let first = try #require(ai.candidates.items.first)
        ai.candidates.setReview(.confirmed, for: first.id)
        for _ in 0..<101 { await ai.ask("Decision?") }
        #expect(ai.insights.count == 100)
        #expect(ai.candidates.items.count == 102)
        #expect(ai.candidates.items.first?.review == .confirmed)
        ai.suspend()
        ai.resume()
        #expect(ai.candidates.items.first?.review == .confirmed)
        ai.reset()
        #expect(ai.candidates.items.isEmpty)
    }
}

@MainActor
private struct CandidateClient: InsightClient {
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        InsightResult(kind: .decisionCandidate, text: "Review before release", evidenceIDs: request.events.map(\.id))
    }
}
