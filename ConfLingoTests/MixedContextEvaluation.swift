import Foundation
import NaturalLanguage
@testable import ConfLingo

struct MixedContextEvaluationCase: Sendable {
    let id: String
    let question: String
    let answerLanguage: String
    let lines: [String]
    var metadataLanguage: String?
    var allowsUndecided = false

    func request() throws -> InsightRequest {
        let session = UUID()
        let events = lines.enumerated().map { index, text in
            TranscriptEvent(id: UUID(), sessionID: session,
                            origin: index.isMultiple(of: 2) ? .microphone : .systemAudio,
                            languageCode: metadataLanguage ?? (index.isMultiple(of: 2) ? "ja-JP" : "en-US"),
                            startOffset: Double(index * 12), endOffset: Double(index * 12 + 8),
                            text: text, isFinal: true, revision: 1, sourceStartTime: Double(index * 12))
        }
        return try InsightRequest(sessionID: session, question: question, trigger: .manual, events: events)
    }

    func qualityIssues(in text: String) -> [String] {
        var issues: [String] = []
        if NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue != answerLanguage {
            issues.append("language")
        }
        let decisionTerms = ["未定", "未決定", "決まっていません", "決まっておらず", "決定していません",
                             "undecided", "not decided", "not been decided", "hasn't been decided",
                             "not set", "not determined", "not scheduled"]
        if !allowsUndecided && decisionTerms.contains(where: text.lowercased().contains) {
            issues.append("unsupportedDecisionStatus")
        }
        return issues
    }

    static let previewLines = Array(repeating: [
        "まずは少人数のパイロットで、実際の利用状況を確認したいですね。",
        "The security review is still in progress. We should have an update by Wednesday.",
        "Can we launch the pilot next Friday, or do we need more time for the security review?",
        "レビューの担当者と、完了条件を確認しましょう。"
    ], count: 3).flatMap { $0 }

    static let all: [Self] = [
        Self(id: "mixed-ja-review", question: "セキュリティレビューは完了したと会話で確認されていますか？",
             answerLanguage: "ja", lines: previewLines),
        Self(id: "mixed-ja-feasibility", question: "来週金曜日にパイロットを開始できると確認されていますか？",
             answerLanguage: "ja", lines: previewLines),
        Self(id: "mixed-en-review", question: "Has the security review been confirmed complete?",
             answerLanguage: "en", lines: previewLines),
        Self(id: "mixed-en-feasibility", question: "Is it known whether the pilot can start next Friday?",
             answerLanguage: "en", lines: previewLines),
        Self(id: "majority-en-ja-question", question: "予算はいくらですか？", answerLanguage: "ja",
             lines: Array(repeating: "The workshop budget is unknown. We need to ask finance.", count: 12),
             metadataLanguage: "en-US"),
        Self(id: "majority-ja-en-question", question: "What is the workshop budget?", answerLanguage: "en",
             lines: Array(repeating: "研修予算の金額は分かりません。経理に聞く必要があります。", count: 12),
             metadataLanguage: "ja-JP"),
        Self(id: "mixed-ja-undecided", question: "開催日は決定済みですか？", answerLanguage: "ja",
             lines: ["The workshop date has not been decided yet.", "日程は未定です。来週相談します。"],
             allowsUndecided: true),
        Self(id: "mixed-en-undecided", question: "Has the workshop date been decided?", answerLanguage: "en",
             lines: ["開催日はまだ決めていません。", "We will discuss the date next week."], allowsUndecided: true)
    ]
}
