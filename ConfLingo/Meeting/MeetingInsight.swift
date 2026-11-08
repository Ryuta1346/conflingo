import Foundation

struct MeetingInsight: Identifiable, Equatable {
    let id = UUID()
    let kind: String
    let text: String
    let priority: Int
    let evidenceIDs: [UUID]

    static func featured(in insights: [Self]) -> Self? {
        insights.reversed().max { $0.priority < $1.priority }
    }
}
