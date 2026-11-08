import Foundation
import Speech
import Translation

/// OS model operations; the service owns request ordering and published UI state.
@MainActor
protocol ModelPreparing {
    func sourceLocales() async -> [Locale]
    func targetLanguages() async -> [Locale.Language]
    func supportedLocale(for identifier: String) async -> Locale?
    func prepareSpeech(for locale: Locale, progress: @escaping @MainActor (Progress) -> Void) async throws -> Bool
    func supportsTranslation(from source: Locale.Language, to target: Locale.Language) async -> Bool
}

struct SystemModelPreparation: ModelPreparing {
    func sourceLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier }
    }

    func targetLanguages() async -> [Locale.Language] {
        // LanguageAvailability is non-Sendable; only its result crosses into MainActor.
        await Task.detached {
            await LanguageAvailability().supportedLanguages
        }.value.sorted { $0.minimalIdentifier < $1.minimalIdentifier }
    }

    func supportedLocale(for identifier: String) async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier))
    }

    func prepareSpeech(for locale: Locale, progress: @escaping @MainActor (Progress) -> Void) async throws -> Bool {
        let transcriber = SpeechTranscriptionService.makeTranscriber(locale: locale)
        let status = await AssetInventory.status(forModules: [transcriber])
        try Task.checkCancellation()
        switch status {
        case .unsupported:
            return false
        case .installed:
            return true
        case .supported, .downloading:
            break
        @unknown default:
            break
        }
        _ = try? await AssetInventory.reserve(locale: locale)
        try Task.checkCancellation()
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try Task.checkCancellation()
            progress(request.progress)
            try await request.downloadAndInstall()
        }
        return true
    }

    func supportsTranslation(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        let status = await LanguageAvailability().status(from: source, to: target)
        switch status {
        case .unsupported: return false
        case .installed, .supported: return true
        @unknown default: return true
        }
    }
}
