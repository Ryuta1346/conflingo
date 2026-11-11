import Foundation

struct MeetingSummaryPlan: Identifiable, Sendable {
    let id = UUID()
    let sessionID: UUID
    let events: [TranscriptEvent]
    let answerLanguage: AnswerLanguage
    let requests: [InsightRequest]
    let knowledgeRevision: UUID?

    init(sessionID: UUID, events: [TranscriptEvent], answerLanguage: AnswerLanguage,
         knowledgeBySection: [[KnowledgeReference]] = [], knowledgeRevision: UUID? = nil) throws {
        let finals = events.filter { $0.sessionID == sessionID && $0.isFinal }
            .sorted { $0.startOffset < $1.startOffset }
        guard !finals.isEmpty else { throw PlanError.empty }
        guard finals.allSatisfy({ $0.startOffset.isFinite && $0.startOffset >= 0
            && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(finals.map(\.id)).count == finals.count else { throw PlanError.invalid }
        guard finals.allSatisfy({ $0.text.count <= 12_000 }) else { throw PlanError.longUtterance }
        var chunks: [[TranscriptEvent]] = []
        var chunk: [TranscriptEvent] = []
        var length = 0
        for event in finals {
            if chunk.count == 30 || length + event.text.count > 12_000 {
                chunks.append(chunk)
                chunk = []
                length = 0
            }
            chunk.append(event)
            length += event.text.count
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        guard chunks.count <= 20 else { throw PlanError.tooManySections }
        self.sessionID = sessionID
        self.events = finals
        self.answerLanguage = answerLanguage
        self.knowledgeRevision = knowledgeRevision
        guard knowledgeBySection.isEmpty || (knowledgeBySection.count == chunks.count && knowledgeRevision != nil) else { throw PlanError.invalid }
        requests = try chunks.enumerated().map { index, events in
            let request = try InsightRequest(
                sessionID: sessionID,
                question: "この区間の会話を簡潔に要約してください。話題、提案、未解決事項と訂正を区別し、根拠発話を示してください。担当者・期限・合意を推測せず、この区間の内容を会議全体の最終決定として扱わないでください。",
                trigger: .manual, events: events, answerLanguage: answerLanguage,
                knowledge: knowledgeBySection.isEmpty ? [] : knowledgeBySection[index], purpose: .summary
            )
            guard request.omittedCount == 0, request.events.count == events.count else { throw PlanError.invalid }
            return request
        }
    }

    enum PlanError: Error, LocalizedError {
        case empty, invalid, longUtterance, tooManySections
        var errorDescription: String? {
            switch self {
            case .empty: "要約できる確定発話がありません。"
            case .invalid: "発話の範囲を確認できないため送信できません。"
            case .longUtterance: "12,000文字を超える発話があるため要約できません。発話はMarkdownに書き出せます。"
            case .tooManySections: "要約の上限（20区間）を超えています。発話を省略せずMarkdownに書き出せます。"
            }
        }
    }
}

struct MeetingSummarySection: Identifiable, Equatable, Sendable {
    let id: UUID
    let text: String
    let evidenceIDs: [UUID]
    let startOffset: TimeInterval
    let endOffset: TimeInterval
    var supplement = ""
    var knowledgeReferences: [KnowledgeReference] = []
}

struct MeetingSummary: Equatable, Sendable {
    let sessionID: UUID
    let answerLanguage: AnswerLanguage
    let sections: [MeetingSummarySection]
}
