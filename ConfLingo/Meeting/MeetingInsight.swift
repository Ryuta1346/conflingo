import Foundation

struct MeetingInsight: Identifiable, Equatable, Sendable, Codable {
    enum Kind: String, Codable, Sendable, CaseIterable {
        case answerSuggestion, followUpQuestion, risk, decisionCandidate, actionCandidate

        var label: String {
            switch self {
            case .answerSuggestion: "回答のヒント"
            case .followUpQuestion: "確認質問の候補"
            case .risk: "リスク"
            case .decisionCandidate: "決定候補"
            case .actionCandidate: "アクション候補"
            }
        }

        var priority: Int { self == .risk ? 2 : 1 }
    }

    enum Status: String, Codable, Sendable { case generating, complete, interrupted }
    var id = UUID()
    let kind: Kind
    var text: String
    let priority: Int
    let evidenceIDs: [UUID]
    var status: Status = .complete
    var hasInvalidEvidence = false
    var knowledgeReferences: [KnowledgeReference] = []
    var webReferences: [WebReference]? = nil
    var searchSuggestionsHTML: String? = nil

    static func featured(in insights: [Self]) -> Self? {
        insights.reversed().max { $0.priority < $1.priority }
    }
}
