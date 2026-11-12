import Foundation
import Speech

enum SpeechRecognitionMode: String, CaseIterable, Identifiable, Sendable {
    case standard, vocabulary
    var id: Self { self }
    var label: String { self == .standard ? "通常の会話認識" : "資料の用語を優先（要比較評価）" }
}

enum VocabularyFailure: Error, LocalizedError {
    case unavailable, inactive
    var errorDescription: String? {
        switch self {
        case .unavailable: "この言語・認識方式では用語ヒントを利用できません。通常の会話認識を選ぶか、対応する言語を選んでください。"
        case .inactive: "認識用語は未反映です。次回の開始時に適用します。"
        }
    }
}

enum RecognitionModule {
    case standard(SpeechTranscriber)
    case vocabulary(DictationTranscriber)

    var module: any SpeechModule {
        switch self {
        case .standard(let value): value
        case .vocabulary(let value): value
        }
    }

    @MainActor
    func consume(_ receive: @escaping @MainActor (SpeechResult) async throws -> Void) async throws {
        switch self {
        case .standard(let value):
            for try await result in value.results {
                try Task.checkCancellation()
                try await receive(.init(text: String(result.text.characters), isFinal: result.isFinal,
                                        startTime: result.range.start.seconds, endTime: result.range.end.seconds))
            }
        case .vocabulary(let value):
            for try await result in value.results {
                try Task.checkCancellation()
                try await receive(.init(text: String(result.text.characters), isFinal: result.isFinal,
                                        startTime: result.range.start.seconds, endTime: result.range.end.seconds))
            }
        }
    }
}
