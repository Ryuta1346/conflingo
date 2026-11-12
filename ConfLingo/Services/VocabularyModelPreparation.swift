import Foundation
import Speech

struct VocabularyModelPreparation: ModelPreparing {
    func sourceLocales() async -> [Locale] { await DictationTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier } }
    func targetLanguages() async -> [Locale.Language] { await SystemModelPreparation().targetLanguages() }
    func supportedLocale(for identifier: String) async -> Locale? {
        await DictationTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }
    func prepareSpeech(for locale: Locale, progress: @escaping @MainActor (Progress) -> Void) async throws -> Bool {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveLongDictation)
        guard await AssetInventory.status(forModules: [transcriber]) != .unsupported else { return false }
        try Task.checkCancellation()
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            progress(installation.progress)
            try await installation.downloadAndInstall()
        }
        return true
    }
    func supportsTranslation(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        await SystemModelPreparation().supportsTranslation(from: source, to: target)
    }
}
