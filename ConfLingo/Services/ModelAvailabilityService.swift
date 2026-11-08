import Foundation
import Observation

/// 選択された認識言語と翻訳ペアの利用可能性を確認し、
/// 必要なら音声認識モデルのダウンロードを行う。
@MainActor
@Observable
final class ModelAvailabilityService {
    private struct PreparationError: LocalizedError {
        let errorDescription: String?
    }

    static func prepareForTranscription(_ locale: Locale) async throws -> Locale {
        let availability = ModelAvailabilityService()
        await availability.checkAndPrepare(sourceLocaleID: locale.identifier, targetLanguageID: nil)
        try Task.checkCancellation()
        guard availability.state == .ready, let prepared = availability.speechLocale else {
            if case .unavailable(let reason) = availability.state { throw PreparationError(errorDescription: reason) }
            throw PreparationError(errorDescription: "認識モデルを準備できませんでした。")
        }
        return prepared
    }

    enum State: Equatable {
        case checking
        case downloadingSpeechModel
        case ready
        case unavailable(String)
    }

    private(set) var state: State = .checking
    private(set) var downloadProgress: Progress?
    private(set) var speechLocale: Locale?
    /// 言語 Picker 用の候補（初回チェック時に取得・キャッシュ）
    private(set) var supportedSourceLocales: [Locale] = []
    private(set) var supportedTargetLanguages: [Locale.Language] = []

    private let backend: any ModelPreparing
    private var requestID = UUID()

    init(backend: any ModelPreparing = SystemModelPreparation()) {
        self.backend = backend
    }

    /// Returns true only when this request has prepared the selected language pair.
    @discardableResult
    func checkAndPrepare(sourceLocaleID: String, targetLanguageID: String?) async -> Bool {
        guard !Task.isCancelled else { return false }
        let request = UUID()
        requestID = request
        func isCurrent() -> Bool { requestID == request && !Task.isCancelled }

        state = .checking
        speechLocale = nil
        downloadProgress = nil
        let sourceName = LanguageCatalog.displayName(for: sourceLocaleID)
        if supportedSourceLocales.isEmpty {
            let locales = await backend.sourceLocales()
            guard isCurrent() else { return false }
            supportedSourceLocales = locales
        }
        if targetLanguageID != nil, supportedTargetLanguages.isEmpty {
            let languages = await backend.targetLanguages()
            guard isCurrent() else { return false }
            supportedTargetLanguages = languages
        }
        let resolvedLocale = await backend.supportedLocale(for: sourceLocaleID)
        guard isCurrent() else { return false }
        guard let locale = resolvedLocale else {
            state = .unavailable("\(sourceName)の音声認識はこのMacでは利用できません。")
            return false
        }
        do {
            let supported = try await backend.prepareSpeech(for: locale) { progress in
                guard isCurrent() else { return }
                self.state = .downloadingSpeechModel
                self.downloadProgress = progress
            }
            guard isCurrent() else { return false }
            downloadProgress = nil
            guard supported else {
                state = .unavailable("\(sourceName)の音声認識モデルがサポートされていません。")
                return false
            }
        } catch {
            guard isCurrent() else { return false }
            downloadProgress = nil
            state = .unavailable("音声認識モデルのダウンロードに失敗しました: \(error.localizedDescription)")
            return false
        }
        if let targetLanguageID {
            let supported = await backend.supportsTranslation(
                from: locale.language, to: Locale.Language(identifier: targetLanguageID)
            )
            guard isCurrent() else { return false }
            guard supported else {
                let targetName = LanguageCatalog.displayName(for: targetLanguageID)
                state = .unavailable("\(sourceName)から\(targetName)への翻訳はこのMacでは利用できません。")
                return false
            }
        }
        speechLocale = locale
        state = .ready
        return true
    }
}
