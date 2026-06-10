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

    func checkAndPrepare() async {
        state = .checking

        // 1. 英語音声認識のサポート確認
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en_US")) else {
            state = .unavailable("英語の音声認識はこのMacでは利用できません。")
            return
        }
        speechLocale = locale

        // 2. 音声認識モデルのインストール確認・ダウンロード
        let transcriber = SpeechTranscriptionService.makeTranscriber(locale: locale)
        let speechStatus = await AssetInventory.status(forModules: [transcriber])
        switch speechStatus {
        case .unsupported:
            state = .unavailable("英語の音声認識モデルがサポートされていません。")
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

        // 3. 英→日翻訳のサポート確認（モデル未DLなら prepareTranslation がDLダイアログを出す）
        let translationStatus = await LanguageAvailability().status(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "ja")
        )
        switch translationStatus {
        case .unsupported:
            state = .unavailable("英語から日本語への翻訳はこのMacでは利用できません。")
        case .installed, .supported:
            state = .ready
        @unknown default:
            state = .ready
        }
    }
}
