import SwiftUI

/// 提案カードの状態表示。文字に加えて、記号と色調も状態ごとに変える。
struct InsightReviewBadge: Equatable {
    enum Tone: Equatable { case positive, neutral, attention }

    let text: String
    let symbol: String
    let tone: Tone

    /// 候補として確認対象になっている場合は確認状態を、それ以外は生成状態を示す。
    init(review: MeetingCandidate.Review?, status: MeetingInsight.Status) {
        if let review {
            text = review.label
            switch review {
            case .confirmed:
                symbol = "checkmark.circle"
                tone = .positive
            case .rejected:
                symbol = "xmark.circle"
                tone = .neutral
            case .unreviewed:
                symbol = "questionmark.circle"
                tone = .attention
            }
        } else {
            switch status {
            case .generating:
                text = "生成中・未検証"
                symbol = "ellipsis.circle"
                tone = .neutral
            case .interrupted:
                text = "中断"
                symbol = "exclamationmark.triangle"
                tone = .attention
            case .complete:
                text = "要確認"
                symbol = "questionmark.circle"
                tone = .attention
            }
        }
    }

    var color: Color {
        switch tone {
        case .positive: DesignTokens.positive
        case .neutral: DesignTokens.secondary
        case .attention: DesignTokens.warning
        }
    }
}
