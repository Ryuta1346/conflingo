import Foundation

enum TranslationState: Equatable, Sendable {
    case pending
    case translating
    case done
    case failed(String)
}

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let english: String
    var japanese: String?
    var translationState: TranslationState
    let finalizedAt: Date
    /// 録音開始からの発話開始位置（秒）。nil は時刻不明。
    let startTime: TimeInterval?
}
