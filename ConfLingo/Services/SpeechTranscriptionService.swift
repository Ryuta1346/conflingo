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
    func prepare(mode: SpeechRecognitionMode, locale: Locale) async throws
    func updateContext(_ keywords: [String]) async throws
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

extension SpeechTranscribing {
    func prepare(mode: SpeechRecognitionMode, locale: Locale) async throws {
        if mode != .standard { throw VocabularyFailure.unavailable }
    }
    func updateContext(_ keywords: [String]) async throws { throw VocabularyFailure.unavailable }
}

@MainActor
final class SpeechTranscriptionService: SpeechTranscribing {
    private let audioSource: any AudioSource
    private let diagnostics: AudioDiagnostics?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, any Error>?
    private var mode: SpeechRecognitionMode = .standard
    private var vocabularyLocale: Locale?

    func prepare(mode: SpeechRecognitionMode, locale: Locale) async throws {
        guard analyzer == nil else { throw VocabularyFailure.inactive }
        self.mode = mode
        vocabularyLocale = nil
        guard mode == .vocabulary else { return }
        guard let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) else { throw VocabularyFailure.unavailable }
        guard try await VocabularyModelPreparation().prepareSpeech(for: supported, progress: { _ in }) else { throw VocabularyFailure.unavailable }
        try Task.checkCancellation()
        vocabularyLocale = supported
    }

    func updateContext(_ keywords: [String]) async throws {
        guard mode == .vocabulary, let analyzer else { throw VocabularyFailure.inactive }
        guard keywords.count <= 100 else { throw DocumentTermFailure.limit }
        let context = AnalysisContext()
        context.contextualStrings = [.general: keywords]
        try await analyzer.setContext(context)
    }

    init(audioSource: any AudioSource = MicrophoneAudioSource(), diagnostics: AudioDiagnostics? = nil) {
        self.diagnostics = diagnostics
        self.audioSource = audioSource
    }

    func startAudioInput(targetFormat: AVAudioFormat) async throws -> AsyncMapSequence<AudioFrameStream, AnalyzerInput> {
        let diagnostics = self.diagnostics
        let origin = audioSource.origin
        return try await audioSource.start(targetFormat: targetFormat).map {
            diagnostics?.record(.consumed, origin: origin, samples: Int($0.buffer.frameLength),
                                sampleRate: $0.buffer.format.sampleRate, channels: $0.buffer.format.channelCount)
            return AnalyzerInput(buffer: $0.buffer)
        }
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
        let transcriber: RecognitionModule
        if mode == .vocabulary {
            guard let vocabularyLocale else { throw VocabularyFailure.unavailable }
            transcriber = .vocabulary(DictationTranscriber(locale: vocabularyLocale, preset: .progressiveLongDictation))
        } else { transcriber = .standard(Self.makeTranscriber(locale: locale, fastResults: fastResults)) }
        let detector = SpeechDetector(
            detectionOptions: .init(sensitivityLevel: .medium),
            reportResults: false
        )
        let analyzer = SpeechAnalyzer(modules: [detector, transcriber.module])
        self.analyzer = analyzer

        do {
            if mode == .vocabulary { try await updateContext(contextKeywords) }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber.module, detector]
            ) else {
                throw TranscriptionError.audioFormatUnavailable
            }
            try Task.checkCancellation()
            let audioStream = try await startAudioInput(targetFormat: format)
            onInputStarted()
            resultsTask = Task {
                do {
                    try await transcriber.consume { [self] result in
                        try Task.checkCancellation()
                        let text = result.text
                        diagnostics?.record(result.isFinal ? .osFinal : .osPartial, origin: audioSource.origin)
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            diagnostics?.record(.osEmpty, origin: audioSource.origin)
                        }
                        try await receive(result)
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
