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

/// OSの認識結果と終了を差し替える境界。音声入力の共通化はPR2で行う。
@MainActor
protocol SpeechTranscribing: AnyObject {
    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws
    func stop() async throws
}

@MainActor
final class SpeechTranscriptionService: SpeechTranscribing {
    private let audioService = AudioCaptureService()
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, any Error>?

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
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        let transcriber = Self.makeTranscriber(locale: locale, fastResults: fastResults)
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: false
        )
        let analyzer = SpeechAnalyzer(modules: [detector, transcriber])
        self.analyzer = analyzer

        do {
            if !contextKeywords.isEmpty {
                let context = AnalysisContext()
                context.contextualStrings = [.general: contextKeywords]
                try await analyzer.setContext(context)
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber, detector]
            ) else {
                throw TranscriptionError.audioFormatUnavailable
            }
            try Task.checkCancellation()
            let audioStream = try audioService.start(targetFormat: format)
            onInputStarted()
            resultsTask = Task {
                do {
                    for try await result in transcriber.results {
                        try Task.checkCancellation()
                        try await receive(SpeechResult(
                            text: String(result.text.characters), isFinal: result.isFinal,
                            startTime: result.range.start.seconds, endTime: result.range.end.seconds
                        ))
                    }
                } catch {
                    if !Task.isCancelled { onFailure(error) }
                    throw error
                }
            }
            try await analyzer.start(inputSequence: audioStream)
        } catch {
            await cancel(analyzer)
            throw error
        }
    }

    /// 終了時に生成されるfinalも、購読側へ発行し終えるまで待つ。
    func stop() async throws {
        audioService.stop()
        guard let analyzer else { return }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await resultsTask?.value
            resultsTask = nil
            self.analyzer = nil
        } catch {
            await cancel(analyzer)
            throw error
        }
    }

    private func cancel(_ analyzer: SpeechAnalyzer) async {
        audioService.stop()
        resultsTask?.cancel()
        await analyzer.cancelAndFinishNow()
        _ = await resultsTask?.result
        resultsTask = nil
        self.analyzer = nil
    }
}
