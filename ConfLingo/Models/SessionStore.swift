import Foundation
import Observation

enum SessionPhase: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case stopping
}

/// UI の単一情報源。セグメント履歴・partial テキスト・セッション状態を保持する。
@MainActor
@Observable
final class SessionStore {
    private(set) var segments: [TranscriptSegment] = []
    private(set) var volatileText: String = ""
    var phase: SessionPhase = .idle
    var sessionName: String = ""
    private(set) var startedAt: Date?

    var untranslatedSegments: [TranscriptSegment] {
        segments.filter { $0.japanese == nil }
    }

    /// final transcript を確定セグメントとして追加する。
    /// 空文字・直前セグメントと同一文は破棄して nil を返す（重複翻訳ガード）。
    @discardableResult
    func appendFinal(_ text: String) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard segments.last?.english != trimmed else { return nil }

        let segment = TranscriptSegment(
            id: UUID(),
            index: segments.count + 1,
            english: trimmed,
            japanese: nil,
            translationState: .pending,
            finalizedAt: Date()
        )
        segments.append(segment)
        volatileText = ""
        return segment.id
    }

    func updateVolatile(_ text: String) {
        volatileText = text
    }

    func beginTranslating(_ id: UUID) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[i].translationState = .translating
    }

    func applyTranslation(id: UUID, japanese: String) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[i].japanese = japanese
        segments[i].translationState = .done
    }

    func markTranslationFailed(id: UUID, reason: String) {
        guard let i = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[i].translationState = .failed(reason)
    }

    func markSessionStarted() {
        if startedAt == nil {
            startedAt = Date()
        }
    }

    func reset() {
        segments = []
        volatileText = ""
        startedAt = nil
    }
}
