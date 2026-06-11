import Foundation

enum TranslationState: Equatable, Sendable {
    case pending
    case translating
    case done
    case failed(String)
}

/// 翻訳の最小単位。複数の確定セグメントを文末まで結合したもの。
/// 英語ペインはセグメント単位で即時表示し、翻訳はこの単位で行う
/// （1リクエスト内に複数文を含めることで翻訳エンジンに文脈を渡す）。
struct TranslationUnit: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    /// この unit を構成する確定セグメントの ID（出現順）
    let segmentIDs: [UUID]
    /// 構成セグメントを結合した翻訳入力テキスト
    let english: String
    var japanese: String?
    var translationState: TranslationState
    /// 先頭セグメントの発話開始位置（秒）。nil は時刻不明。
    let startTime: TimeInterval?
}
