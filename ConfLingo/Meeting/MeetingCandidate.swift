import Foundation
import Observation

struct MeetingCandidate: Identifiable, Equatable, Sendable, Codable {
    enum Review: String, CaseIterable, Sendable, Codable {
        case unreviewed, confirmed, rejected
        var label: String {
            switch self {
            case .unreviewed: "未確認"
            case .confirmed: "確認済み"
            case .rejected: "却下"
            }
        }
    }

    let sessionID: UUID
    let insight: MeetingInsight
    var review: Review = .unreviewed
    var id: UUID { insight.id }
    var evidenceIDs: [UUID] { insight.evidenceIDs }
}

@MainActor
@Observable
final class MeetingCandidateStore {
    private(set) var items: [MeetingCandidate] = []
    private let transcript: MeetingSessionStore

    init(transcript: MeetingSessionStore) { self.transcript = transcript }

    func receive(_ card: MeetingInsight, sessionID: UUID) {
        guard sessionID == transcript.sessionID, card.status == .complete,
              card.kind == .decisionCandidate || card.kind == .actionCandidate,
              !card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !items.contains(where: { $0.id == card.id }) else { return }
        items.append(MeetingCandidate(sessionID: sessionID, insight: card))
    }

    func canConfirm(_ id: UUID) -> Bool {
        guard let candidate = items.first(where: { $0.id == id }),
              candidate.sessionID == transcript.sessionID, !candidate.insight.hasInvalidEvidence,
              !candidate.evidenceIDs.isEmpty else { return false }
        let available = Set(transcript.finals.map(\.id))
        return candidate.evidenceIDs.allSatisfy { available.contains($0) }
    }

    func setReview(_ review: MeetingCandidate.Review, for id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.sessionID == transcript.sessionID }),
              review != .confirmed || canConfirm(id) else { return }
        items[index].review = review
    }

    func reset() { items = [] }
}
