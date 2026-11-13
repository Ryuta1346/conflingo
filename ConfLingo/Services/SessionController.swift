import Foundation
import Observation

/// 共通の音声入力経路をConferenceの字幕・翻訳へ接続する。
@MainActor
@Observable
final class SessionController {
    private let dual: DualTranscriptionController
    var activity: AudioInputUse { dual.activity }
    var isStopping: Bool { dual.isStopping }
    var lastError: String? { dual.lastError ?? sessionError }
    private var sessionError: String?
    private var adapter: LegacyTranslationAdapter?
    private var consumer: Task<Void, Never>?

    init(
        audioSource: any AudioSource = MicrophoneAudioSource(),
        speechService: (any SpeechTranscribing)? = nil,
        timeline: MeetingTimeline = MeetingTimeline(),
        activity: AudioInputUse = AudioInputUse(),
        dualController: DualTranscriptionController? = nil
    ) {
        dual = dualController ?? DualTranscriptionController(
            microphone: audioSource, microphoneSpeech: speechService,
            timeline: timeline, activity: activity, owner: .conference, prepareModel: { $0 })
    }

    func start(
        store: SessionStore,
        coordinator: TranslationCoordinator,
        locale: Locale,
        glossary: [KeywordParser.GlossaryEntry] = [],
        fastResults: Bool = false,
        recognitionMode: SpeechRecognitionMode = .standard,
        selection: AudioInputSelection = .microphone
    ) async {
        guard store.phase == .idle, dual.phase == .idle, !Task.isCancelled else { return }
        store.sourceLanguage = locale.identifier
        sessionError = nil
        store.setActiveGlossary(glossary)
        dual.phaseChanged = { phase in
            store.phase = phase
            if phase == .listening { store.markSessionStarted() }
        }
        dual.prepareOptionalConsumer = { [weak self] hub in
            guard let self else { return }
            let adapter = LegacyTranslationAdapter(
                sessionID: self.dual.store.sessionID, store: store, coordinator: coordinator,
                origins: selection.origins, commonTimeline: selection != .microphone)
            self.adapter = adapter
            let subscription = await hub.subscribe()
            self.consumer = Task { [weak self] in
                do {
                    while let event = try await subscription.next() { adapter.receive(event) }
                } catch {
                    self?.sessionError = "字幕の処理が追いつかないため入力を停止します。最後の発話が欠けている可能性があります。"
                    // この購読の終了を待つstopは、別タスクで開始する。
                    Task { [weak self] in await self?.dual.stop() }
                }
                await subscription.cancel()
            }
        }
        dual.finishOptionalConsumer = { [weak self] in
            await self?.finishEvents(store: store, coordinator: coordinator)
        }
        await dual.start(
            microphoneLocale: locale, systemLocale: locale, fastResults: fastResults,
            recognitionMode: recognitionMode,
            contextKeywords: [.microphone: glossary.map(\.term), .systemAudio: glossary.map(\.term)],
            selection: selection)
    }

    func stop(store: SessionStore, coordinator: TranslationCoordinator) async {
        await dual.stop()
    }

    func reset(store: SessionStore) {
        guard store.phase == .idle, dual.phase == .idle else { return }
        dual.clear()
        store.reset()
        sessionError = nil
    }

    func updateContext(_ keywords: [String], store: SessionStore) async -> Bool {
        guard store.phase == .listening else { return false }
        return await dual.updateContext([.microphone: keywords, .systemAudio: keywords])
    }

    private func finishEvents(store: SessionStore, coordinator: TranslationCoordinator) async {
        await consumer?.value
        consumer = nil
        await adapter?.finish()
        adapter = nil
        // イベント配信開始前から保留されていた翻訳単位も確定する。
        if let unit = store.flushBuffer() { coordinator.enqueue(id: unit.id, text: unit.english) }
        store.updateVolatile("")
    }
}
