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

/// OSの認識結果と終了を差し替える境界。
@MainActor
protocol SpeechTranscribing: AnyObject {
    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws
    func stop() async throws
    func stopInput() async throws
    func finishRecognition() async throws
    func cancelRecognition() async
}

@MainActor
final class SpeechTranscriptionService: SpeechTranscribing {
    private let audioSource: any AudioSource
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, any Error>?

    init(audioSource: any AudioSource = MicrophoneAudioSource()) {
        self.audioSource = audioSource
    }

    func startAudioInput(targetFormat: AVAudioFormat) async throws -> AsyncMapSequence<AudioFrameStream, AnalyzerInput> {
        try await audioSource.start(targetFormat: targetFormat).map { AnalyzerInput(buffer: $0.buffer) }
    }

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
            let audioStream = try await startAudioInput(targetFormat: format)
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
            try await cancel(analyzer)
            throw error
        }
    }

    /// 終了時に生成されるfinalも、購読側へ発行し終えるまで待つ。
    func stop() async throws {
        do {
            try await stopInput()
            try await finishRecognition()
        } catch {
            await cancelRecognition()
            throw error
        }
    }

    func stopInput() async throws {
        try await audioSource.stop()
    }

    func finishRecognition() async throws {
        guard let analyzer else {
            return
        }
        do {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await resultsTask?.value
            resultsTask = nil
            self.analyzer = nil
        } catch {
            await cancelRecognition()
            throw error
        }
    }

    func cancelRecognition() async {
        resultsTask?.cancel()
        await analyzer?.cancelAndFinishNow()
        _ = await resultsTask?.result
        resultsTask = nil
        analyzer = nil
    }

    private func cancel(_ analyzer: SpeechAnalyzer) async throws {
        var stopError: (any Error)?
        do { try await audioSource.stop() } catch { stopError = error }
        resultsTask?.cancel()
        await analyzer.cancelAndFinishNow()
        _ = await resultsTask?.result
        resultsTask = nil
        self.analyzer = nil
        if let stopError { throw stopError }
    }
}
