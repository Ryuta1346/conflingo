import Foundation

/// 音声認識の確定単位。英語ペインの即時表示に使う。
/// 翻訳状態は持たない（翻訳は文末まで結合した TranslationUnit 単位で行う）。
struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let english: String
    let finalizedAt: Date
    /// 録音開始からの発話開始位置（秒）。nil は時刻不明。
    let startTime: TimeInterval?
}
