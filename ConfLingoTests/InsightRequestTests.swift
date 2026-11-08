import Foundation
import Testing
@testable import ConfLingo

struct InsightRequestTests {
    @Test func sendsOnlyFinalsInThisSessionWithinBounds() throws {
        let session = UUID()
        let final = insightEvent(session: session, text: "確認する内容", offset: 2)
        let request = try InsightRequest(sessionID: session, question: "  何を確認する？  ", trigger: .manual,
                                         events: [insightEvent(session: UUID()), insightEvent(session: session, final: false),
                                                  insightEvent(session: session, text: String(repeating: "a", count: 12_001)), final])
        #expect(request.question == "何を確認する？")
        #expect(request.events == [final])
        #expect(request.omittedCount == 1)
    }

    @Test func boundsContextAndRejectsInvalidQuestions() throws {
        let session = UUID()
        let events = (0..<40).map { insightEvent(session: session, text: "line \($0)", offset: Double($0)) }
        let request = try InsightRequest(sessionID: session, question: "What next?", trigger: .manual, events: events)
        #expect(request.events.count == 30)
        #expect(request.events.first?.text == "line 10")
        #expect(request.omittedCount == 10)
        #expect(throws: InsightFailure.invalidQuestion) {
            try InsightRequest(sessionID: session, question: " ", trigger: .manual, events: events)
        }
        #expect(throws: InsightFailure.invalidQuestion) {
            try InsightRequest(sessionID: session, question: String(repeating: "あ", count: 2_001),
                               trigger: .manual, events: events)
        }
    }

    @Test func unknownEvidenceIsNotInventedAndCandidateRemainsUnconfirmed() throws {
        let event = insightEvent()
        let result = InsightResult(kind: .decisionCandidate, text: "金曜を候補にする", evidenceIDs: [event.id, UUID()])
        let request = try InsightRequest(sessionID: event.sessionID, question: "決定は？", trigger: .manual, events: [event])
        let card = try result.card(for: request)
        #expect(card.id == request.id)
        #expect(card.evidenceIDs == [event.id])
        #expect(card.hasInvalidEvidence)
        #expect(card.kind == .decisionCandidate)
        #expect(card.status == .complete)
    }
}

func insightEvent(session: UUID = UUID(), text: String = "Can we proceed?", offset: Double = 0,
                  final: Bool = true) -> TranscriptEvent {
    TranscriptEvent(id: UUID(), sessionID: session, origin: .systemAudio, languageCode: "en-US",
                    startOffset: offset, endOffset: offset + 1, text: text, isFinal: final, revision: 1, sourceStartTime: offset)
}
