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
    /// 文末が来ないまま放置されたバッファを強制 flush するまでの待ち時間。
    /// 句読点を発しない話者でも字幕遅延がこの値を超えて伸びないようにする。
    static let bufferFlushTimeout: Duration = .seconds(4)

    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?

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
        // VAD モジュール。拍手・BGM 等の非音声区間を検出し、誤認識テキストの混入を抑える
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: false
        )
        let analyzer = SpeechAnalyzer(modules: [detector, transcriber])
        self.analyzer = analyzer

        // 専門用語（固有名詞・技術用語）を contextual strings として登録し認識精度を上げる
        if !contextKeywords.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: contextKeywords]
            try await analyzer.setContext(context)
        }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber, detector]) else {
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
                        if let id = store.appendFinal(text, startTime: startTime) {
                            self.scheduleTranslation(of: id, store: store, coordinator: coordinator)
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

    /// 確定セグメントを翻訳単位バッファへ積み、文末で確定したら翻訳キューに入れる。
    /// 文末待ちの場合はタイムアウトで強制 flush するタスクを（再）スケジュールする。
    private func scheduleTranslation(
        of segmentID: UUID,
        store: SessionStore,
        coordinator: TranslationCoordinator
    ) {
        flushTask?.cancel()
        if let unit = store.bufferSegment(segmentID) {
            coordinator.enqueue(id: unit.id, text: unit.english)
        } else {
            flushTask = Task {
                try? await Task.sleep(for: Self.bufferFlushTimeout)
                guard !Task.isCancelled else { return }
                if let unit = store.flushBuffer() {
                    coordinator.enqueue(id: unit.id, text: unit.english)
                }
            }
        }
    }

    /// 音声入力を止め、残りの volatile を final 化してから解析を終了する。
    func stop(audioService: AudioCaptureService) async {
        audioService.stop()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        flushTask?.cancel()
        flushTask = nil
        resultsTask = nil
        analyzer = nil
    }
}
