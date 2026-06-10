import AVFAudio
import CoreMedia
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

    /// fastResults は確定レイテンシと精度のトレードオフ。翻訳しない（文字起こしのみ）
    /// セッションでのみ速度を優先する。
    nonisolated static func reportingOptions(fastResults: Bool) -> Set<SpeechTranscriber.ReportingOption> {
        fastResults ? [.volatileResults, .fastResults] : [.volatileResults]
    }

    static func makeTranscriber(locale: Locale, fastResults: Bool = false) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: Self.reportingOptions(fastResults: fastResults),
            attributeOptions: []
        )
    }

    func start(
        locale: Locale,
        contextKeywords: [String],
        fastResults: Bool,
        store: SessionStore,
        audioService: AudioCaptureService,
        coordinator: TranslationCoordinator
    ) async throws {
        let transcriber = Self.makeTranscriber(locale: locale, fastResults: fastResults)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // 専門用語（固有名詞・技術用語）を contextual strings として登録し認識精度を上げる
        if !contextKeywords.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextKeywords]
            try await analyzer.setContext(context)
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let audioStream = try audioService.start(targetFormat: format)

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        // 録音開始からの発話位置（秒）。invalid CMTime は NaN になるため除外
                        let seconds = result.range.start.seconds
                        let startTime = seconds.isFinite ? seconds : nil
                        if let id = store.appendFinal(text, startTime: startTime),
                           let segment = store.segments.last {
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
