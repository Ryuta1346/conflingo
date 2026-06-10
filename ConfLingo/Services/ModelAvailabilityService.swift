import Foundation
import Observation
import Speech
import Translation

/// 起動時に英語音声認識モデルと英→日翻訳の利用可能性を確認し、
/// 必要なら音声認識モデルのダウンロードを行う。
@MainActor
@Observable
final class ModelAvailabilityService {
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

    /// targetLanguageID が nil の場合は文字起こしのみモードとみなし、翻訳ペアの確認をスキップする
    func checkAndPrepare(sourceLocaleID: String, targetLanguageID: String?) async {
        state = .checking
        let sourceName = LanguageCatalog.displayName(for: sourceLocaleID)

        // 0. 言語 Picker 用の候補を取得
        // LanguageAvailability は非 Sendable のため、変数に保持せず呼び出しごとに生成する
        if supportedSourceLocales.isEmpty {
            supportedSourceLocales = await SpeechTranscriber.supportedLocales
                .sorted { $0.identifier < $1.identifier }
        }
        if supportedTargetLanguages.isEmpty {
            // 非 Sendable な LanguageAvailability の async プロパティは MainActor から
            // 直接読めないため、nonisolated なタスク内で取得する（返り値は Sendable）
            supportedTargetLanguages = await Task.detached {
                await LanguageAvailability().supportedLanguages
            }.value.sorted { $0.minimalIdentifier < $1.minimalIdentifier }
        }

        // 1. 認識言語のサポート確認
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: sourceLocaleID)) else {
            state = .unavailable("\(sourceName)の音声認識はこのMacでは利用できません。")
            return
        }
        speechLocale = locale

        // 2. 音声認識モデルのインストール確認・ダウンロード
        let transcriber = SpeechTranscriptionService.makeTranscriber(locale: locale)
        let speechStatus = await AssetInventory.status(forModules: [transcriber])
        switch speechStatus {
        case .unsupported:
            state = .unavailable("\(sourceName)の音声認識モデルがサポートされていません。")
            return
        case .installed:
            break
        case .supported, .downloading:
            fallthrough
        @unknown default:
            do {
                _ = try? await AssetInventory.reserve(locale: locale)
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                    state = .downloadingSpeechModel
                    downloadProgress = request.progress
                    try await request.downloadAndInstall()
                    downloadProgress = nil
                }
            } catch {
                state = .unavailable("音声認識モデルのダウンロードに失敗しました: \(error.localizedDescription)")
                return
            }
        }

        // 3. 翻訳ペアのサポート確認（モデル未DLなら prepareTranslation がDLダイアログを出す）
        guard let targetLanguageID else {
            state = .ready
            return
        }
        let targetName = LanguageCatalog.displayName(for: targetLanguageID)
        let translationStatus = await LanguageAvailability().status(
            from: locale.language,
            to: Locale.Language(identifier: targetLanguageID)
        )
        switch translationStatus {
        case .unsupported:
            state = .unavailable("\(sourceName)から\(targetName)への翻訳はこのMacでは利用できません。")
        case .installed, .supported:
            state = .ready
        @unknown default:
            state = .ready
        }
    }
}
