import Foundation
import Observation

/// Start / Stop の状態遷移と、音声入力・文字起こしサービスの編成を担う。
@MainActor
@Observable
final class SessionController {
    private let audioService = AudioCaptureService()
    private let speechService = SpeechTranscriptionService()
    private(set) var lastError: String?

    func start(store: SessionStore, coordinator: TranslationCoordinator, locale: Locale) async {
        guard store.phase == .idle else { return }
        store.phase = .preparing
        lastError = nil

        guard await AudioCaptureService.requestPermission() else {
            lastError = "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で ConfLingo を許可してください。"
            store.phase = .idle
            return
        }

        do {
            try await speechService.start(
                locale: locale,
                store: store,
                audioService: audioService,
                coordinator: coordinator
            )
            store.markSessionStarted()
            store.phase = .listening
        } catch {
            audioService.stop()
            lastError = "文字起こしを開始できませんでした: \(error.localizedDescription)"
            store.phase = .idle
        }
    }

    func stop(store: SessionStore) async {
        guard store.phase == .listening else { return }
        store.phase = .stopping
        await speechService.stop(audioService: audioService)
        store.phase = .idle
    }
}
