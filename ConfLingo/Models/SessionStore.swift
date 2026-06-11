import Foundation
import Observation

enum SessionPhase: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case stopping
}

/// UI の単一情報源。セグメント履歴・翻訳単位・partial テキスト・セッション状態を保持する。
@MainActor
@Observable
final class SessionStore {
    /// バッファ flush の暴走ガード。文末が来なくてもこの結合長／セグメント数で強制確定する。
    static let maxBufferedCharacters = 400
    static let maxBufferedSegments = 4

    private(set) var segments: [TranscriptSegment] = []
    /// ID 引きの逆引きインデックス。bufferedSegments が segments を線形探索しないため。
    private var segmentByID: [UUID: TranscriptSegment] = [:]
    private(set) var units: [TranslationUnit] = []
    /// 文末待ちで翻訳単位に未確定のセグメント ID（出現順）
    private(set) var bufferedSegmentIDs: [UUID] = []
    private(set) var volatileText: String = ""
    var phase: SessionPhase = .idle
    var sessionName: String = ""
    private(set) var startedAt: Date?

    /// Start 時点で確定した専門用語辞書。翻訳時の do-not-translate / 訳語固定リストとして参照する。
    private(set) var activeGlossary: [KeywordParser.GlossaryEntry] = []

    var untranslatedUnits: [TranslationUnit] {
        units.filter { $0.japanese == nil }
    }

    /// final transcript を確定セグメントとして追加する。
    /// 空文字・直前セグメントと同一文は破棄して nil を返す（重複翻訳ガード）。
    @discardableResult
    func appendFinal(_ text: String, startTime: TimeInterval? = nil) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard segments.last?.english != trimmed else { return nil }

        let segment = TranscriptSegment(
            id: UUID(),
            index: segments.count + 1,
            english: trimmed,
            finalizedAt: Date(),
            startTime: startTime
        )
        segments.append(segment)
        segmentByID[segment.id] = segment
        volatileText = ""
        return segment.id
    }

    /// 確定セグメントを翻訳単位バッファに積む。文末・結合長・セグメント数のいずれかの
    /// flush 条件を満たしたら翻訳単位を確定して返し、それ以外は nil（文末待ち）。
    @discardableResult
    func bufferSegment(_ id: UUID) -> TranslationUnit? {
        guard let segment = segmentByID[id] else { return nil }
        bufferedSegmentIDs.append(id)

        let combinedLength = bufferedSegments.reduce(0) { $0 + $1.english.count + 1 }
        if SentenceBoundary.endsSentence(segment.english)
            || combinedLength >= Self.maxBufferedCharacters
            || bufferedSegmentIDs.count >= Self.maxBufferedSegments {
            return flushBuffer()
        }
        return nil
    }

    /// バッファ内のセグメントを文末を待たずに翻訳単位として確定する
    /// （タイムアウト・Stop 時用）。バッファが空なら nil。
    @discardableResult
    func flushBuffer() -> TranslationUnit? {
        let buffered = bufferedSegments
        guard !buffered.isEmpty else { return nil }

        let unit = TranslationUnit(
            id: UUID(),
            index: units.count + 1,
            segmentIDs: buffered.map(\.id),
            english: buffered.map(\.english).joined(separator: " "),
            japanese: nil,
            translationState: .pending,
            startTime: buffered.first?.startTime
        )
        units.append(unit)
        bufferedSegmentIDs = []
        return unit
    }

    private var bufferedSegments: [TranscriptSegment] {
        bufferedSegmentIDs.compactMap { segmentByID[$0] }
    }

    func updateVolatile(_ text: String) {
        volatileText = text
    }

    func beginTranslating(_ id: UUID) {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return }
        units[i].translationState = .translating
    }

    func applyTranslation(id: UUID, japanese: String) {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return }
        units[i].japanese = japanese
        units[i].translationState = .done
    }

    func markTranslationFailed(id: UUID, reason: String) {
        guard let i = units.firstIndex(where: { $0.id == id }) else { return }
        units[i].translationState = .failed(reason)
    }

    func setActiveGlossary(_ glossary: [KeywordParser.GlossaryEntry]) {
        activeGlossary = glossary
    }

    func markSessionStarted() {
        if startedAt == nil {
            startedAt = Date()
        }
    }

    func reset() {
        segments = []
        segmentByID = [:]
        units = []
        bufferedSegmentIDs = []
        volatileText = ""
        startedAt = nil
    }
}
