import Foundation
@testable import ConfLingo

struct FocusedResponseEvaluationCase: Sendable {
    let sample: MixedContextEvaluationCase
    var forbiddenPhrases: [String] = []
    var id: String { sample.id }

    func qualityIssues(in text: String) -> [String] {
        var issues = sample.qualityIssues(in: text)
        // Fixture-specific screening; equivalent temporal wording and grounding still need semantic review.
        if forbiddenPhrases.contains(where: text.lowercased().contains) {
            issues.append("unsupportedDetail")
        }
        return issues
    }

    static let all: [Self] = [
        Self(sample: .init(id: "focus-ja-review", question: "セキュリティレビューは完了していますか？",
                           answerLanguage: "ja", lines: MixedContextEvaluationCase.previewLines),
             forbiddenPhrases: ["パイロット", "金曜"]),
        Self(sample: .init(id: "focus-en-review", question: "Has the security review been confirmed complete?",
                           answerLanguage: "en", lines: MixedContextEvaluationCase.previewLines),
             forbiddenPhrases: ["pilot", "friday"]),
        Self(sample: .init(id: "deadline-en-ja", question: "更新情報はいつ得られる見込みですか？",
                           answerLanguage: "ja", lines: ["We expect an update by Wednesday."], metadataLanguage: "en-US"),
             forbiddenPhrases: ["水曜日に", "水曜に", "水曜日当日", "水曜当日"]),
        Self(sample: .init(id: "date-en-ja", question: "更新情報はいつ得られる見込みですか？",
                           answerLanguage: "ja", lines: ["We expect an update on Wednesday."], metadataLanguage: "en-US"),
             forbiddenPhrases: ["水曜日まで", "水曜まで"]),
        Self(sample: .init(id: "deadline-ja-en", question: "When is an update expected?",
                           answerLanguage: "en", lines: ["水曜日までに更新情報が得られる見込みです。"], metadataLanguage: "ja-JP"),
             forbiddenPhrases: ["on wednesday"]),
        Self(sample: .init(id: "date-ja-en", question: "When is an update expected?",
                           answerLanguage: "en", lines: ["水曜日に更新情報が得られる見込みです。"], metadataLanguage: "ja-JP"),
             forbiddenPhrases: ["by wednesday", "no later than wednesday"]),
        Self(sample: .init(id: "long-ja-question",
                           question: "この会話について、レビューの現在の進捗、更新情報が得られる見込み、開始の可否でまだ分からないこと、提案されている確認事項を区別して説明してください。発話にない事実や合意を補わず、分かっている範囲をまとめてください。",
                           answerLanguage: "ja", lines: Array(repeating: [
                               "The security review is still in progress.",
                               "We expect an update by Wednesday.",
                               "Can we launch the pilot next Friday?",
                               "Let's clarify the review owner and completion criteria."
                           ], count: 3).flatMap { $0 }, metadataLanguage: "en-US")),
        Self(sample: .init(id: "long-en-question",
                           question: "Explain the current review progress, when an update is expected, what is still unknown about whether the pilot can start, and the proposed clarifications. Separate stated facts from unknowns and proposals without inventing facts or agreements.",
                           answerLanguage: "en", lines: Array(repeating: [
                               "セキュリティレビューは現在進行中です。",
                               "水曜日までに更新情報が得られる見込みです。",
                               "来週金曜日にパイロットを開始できますか？",
                               "レビューの担当者と完了条件を確認しましょう。"
                           ], count: 3).flatMap { $0 }, metadataLanguage: "ja-JP"))
    ]
}
