import Foundation
import Observation
import os

/// Start / Stop の状態遷移と、音声入力・文字起こしサービスの編成を担う。
@MainActor
@Observable
final class SessionController {
    private static let logger = Logger(subsystem: "com.gavrri.conflingo", category: "session")
    private let audioService = AudioCaptureService()
    private let speechService = SpeechTranscriptionService()
    private(set) var lastError: String?

    func start(
        store: SessionStore,
        coordinator: TranslationCoordinator,
        locale: Locale,
        glossary: [KeywordParser.GlossaryEntry] = [],
        fastResults: Bool = false
    ) async {
        Self.logger.info("start requested: glossary=\(glossary.count)")
        guard store.phase == .idle else { return }
        store.phase = .preparing
        lastError = nil

        guard await AudioCaptureService.requestPermission() else {
            Self.logger.error("microphone permission denied")
            lastError = "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で ConfLingo を許可してください。"
            store.phase = .idle
            return
        }

        do {
            try await speechService.start(
                locale: locale,
                contextKeywords: glossary.map(\.term),
                fastResults: fastResults,
                store: store,
                audioService: audioService,
                coordinator: coordinator
            )
            store.setActiveGlossary(glossary)
            store.markSessionStarted()
            store.phase = .listening
            Self.logger.info("listening started")
        } catch {
            audioService.stop()
            lastError = "文字起こしを開始できませんでした: \(error.localizedDescription)"
            store.phase = .idle
            Self.logger.error("start failed: \(error)")
        }
    }

    func stop(store: SessionStore, coordinator: TranslationCoordinator) async {
        guard store.phase == .listening else { return }
        store.phase = .stopping
        await speechService.stop(audioService: audioService)
        // 文末待ちのまま残ったバッファを翻訳単位として確定する
        if let unit = store.flushBuffer() {
            coordinator.enqueue(id: unit.id, text: unit.english)
        }
        store.phase = .idle
    }
}
