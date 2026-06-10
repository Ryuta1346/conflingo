import AVFAudio
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .audioFormatUnavailable:
            "音声認識に対応するオーディオフォーマットを取得できませんでした。"
        }
    }
}

/// SpeechAnalyzer / SpeechTranscriber を配線し、認識結果を SessionStore と
/// TranslationCoordinator へ流す。
@MainActor
final class SpeechTranscriptionService {
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
    }

    func start(
        locale: Locale,
        store: SessionStore,
        audioService: AudioCaptureService,
        coordinator: TranslationCoordinator
    ) async throws {
        let transcriber = Self.makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let audioStream = try audioService.start(targetFormat: format)

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        if let id = store.appendFinal(text), let segment = store.segments.last {
                            coordinator.enqueue(id: id, text: segment.english)
                        }
                    } else {
                        store.updateVolatile(text)
                    }
                }
            } catch {
                store.updateVolatile("")
            }
        }

        try await analyzer.start(inputSequence: audioStream)
    }

    /// 音声入力を止め、残りの volatile を final 化してから解析を終了する。
    func stop(audioService: AudioCaptureService) async {
        audioService.stop()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask = nil
        analyzer = nil
    }
}
