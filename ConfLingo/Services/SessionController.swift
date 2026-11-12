import Foundation
import Observation
import os

/// 認識、イベント購読、翻訳の開始・終了順序を管理する。
@MainActor
@Observable
final class SessionController {
    private static let logger = Logger(subsystem: "com.gavrri.conflingo", category: "session")
    private let speechService: any SpeechTranscribing
    private let audioSource: any AudioSource
    let activity: AudioInputUse
    private var usageToken: UUID?
    private var dual: DualTranscriptionController?
    private var usingDual = false
    var isStopping: Bool { stopTask != nil || (usingDual && dual?.isStopping == true) }
    private let requestPermission: @MainActor () async -> Bool
    private let timeline: MeetingTimeline
    let meetingStore: MeetingSessionStore
    private var sessionError: String?
    private(set) var lastError: String? {
        get { usingDual ? dual?.lastError ?? sessionError : sessionError }
        set { sessionError = newValue }
    }
    private var hub: TranscriptEventHub?
    private var adapter: LegacyTranslationAdapter?
    private var consumers: [Task<Void, Never>] = []
    private var normalizer: TranscriptEventNormalizer?
    private var runID: UUID?
    private var runFailure: (any Error)?
    private var stopTask: Task<Void, Never>?

    init(
        audioSource: any AudioSource = MicrophoneAudioSource(),
        speechService: (any SpeechTranscribing)? = nil,
        requestPermission: (@MainActor () async -> Bool)? = nil,
        timeline: MeetingTimeline = MeetingTimeline(),
        activity: AudioInputUse = AudioInputUse(),
        dualController: DualTranscriptionController? = nil
    ) {
        self.dual = dualController
        self.audioSource = audioSource
        self.activity = activity
        self.speechService = speechService ?? SpeechTranscriptionService(audioSource: audioSource)
        self.requestPermission = requestPermission ?? { await audioSource.requestPermission() }
        self.timeline = timeline
        meetingStore = MeetingSessionStore(sessionID: timeline.sessionID)
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
        guard store.phase == .idle, !Task.isCancelled else { return }
        store.sourceLanguage = locale.identifier
        if selection != .microphone || usingDual {
            await startSelected(store: store, coordinator: coordinator, locale: locale, glossary: glossary,
                                fastResults: fastResults, recognitionMode: recognitionMode, selection: selection)
            return
        }
        guard let token = activity.acquire(.conference) else {
            lastError = activity.busyMessage
            return
        }
        usageToken = token
        store.phase = .preparing
        lastError = nil
        runFailure = nil
        let permitted = await requestPermission()
        guard !Task.isCancelled else {
            store.phase = .idle
            releaseInputUse()
            return
        }
        guard permitted else {
            lastError = "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で ConfLingo を許可してください。"
            store.phase = .idle
            releaseInputUse()
            return
        }

        let currentRun = UUID()
        runID = currentRun
        let hub = TranscriptEventHub()
        self.hub = hub
        let legacy = await hub.subscribe()
        let meeting = await hub.subscribe()
        let requiredIDs: Set<UUID> = [legacy.id, meeting.id]
        let adapter = LegacyTranslationAdapter(sessionID: timeline.sessionID, store: store, coordinator: coordinator)
        self.adapter = adapter
        consumers = [
            consume(legacy, run: currentRun, store: store, coordinator: coordinator) { adapter.receive($0) },
            consume(meeting, run: currentRun, store: store, coordinator: coordinator) { [meetingStore] in
                meetingStore.receive($0)
            }
        ]

        do {
            try Task.checkCancellation()
            try await speechService.prepare(mode: recognitionMode, locale: locale)
            try await speechService.start(
                locale: locale, contextKeywords: glossary.map(\.term), fastResults: fastResults,
                onInputStarted: { [weak self] in
                    guard let self, self.runID == currentRun else { return }
                    store.setActiveGlossary(glossary)
                    self.normalizer = TranscriptEventNormalizer(
                        sessionID: self.timeline.sessionID, origin: .microphone,
                        languageCode: locale.identifier, inputOffset: self.timeline.beginInput()
                    )
                },
                receive: { [weak self] result in
                    guard let self, self.runID == currentRun,
                          let event = self.normalizer?.makeEvent(result, receivedOffset: self.timeline.offset) else { return }
                    let failed = try await hub.publish(event)
                    if !failed.isDisjoint(with: requiredIDs) { throw TranscriptEventHub.Failure.overflow }
                },
                onFailure: { [weak self] error in
                    self?.recordFailure(error, run: currentRun, store: store, coordinator: coordinator)
                }
            )
            try Task.checkCancellation()
            if let runFailure { throw runFailure }
            store.markSessionStarted()
            store.phase = .listening
            Self.logger.info("listening started")
        } catch {
            if lastError == nil { lastError = "文字起こしを開始できませんでした: \(error.localizedDescription)" }
            try? await speechService.stop()
            runID = nil
            await finishEvents(store: store, coordinator: coordinator)
            finishInputUse(store: store)
        }
    }

    func stop(store: SessionStore, coordinator: TranslationCoordinator) async {
        if usingDual { await dual?.stop(); return }
        if let stopTask {
            await stopTask.value
            return
        }
        guard store.phase == .listening || store.phase == .stopping else { return }
        store.phase = .stopping
        let task = Task {
            do {
                try await speechService.stop()
            } catch {
                if lastError == nil { lastError = "文字起こしを終了できませんでした: \(error.localizedDescription)" }
            }
            runID = nil
            await finishEvents(store: store, coordinator: coordinator)
            stopTask = nil
            finishInputUse(store: store)
        }
        stopTask = task
        await task.value
    }

    func reset(store: SessionStore) {
        guard store.phase == .idle else { return }
        if let dual { dual.clear() } else { timeline.reset() }
        usingDual = false
        meetingStore.reset(sessionID: timeline.sessionID)
        store.reset()
        lastError = nil
    }

    func updateContext(_ keywords: [String], store: SessionStore) async -> Bool {
        if usingDual { return await dual?.updateContext([.microphone: keywords, .systemAudio: keywords]) ?? false }
        guard store.phase == .listening, let run = runID else { return false }
        do {
            try await speechService.updateContext(keywords)
            return runID == run && store.phase == .listening
        } catch { return false }
    }

    private func finishInputUse(store: SessionStore) {
        if audioSource.state == .idle {
            releaseInputUse()
            store.phase = .idle
        } else {
            store.phase = .stopping
            lastError = "音声入力の停止を完了できませんでした。停止を再試行してください。"
        }
    }

    private func releaseInputUse() {
        activity.release(usageToken)
        usageToken = nil
    }

    private func consume(
        _ subscription: TranscriptEventHub.Subscription, run: UUID,
        store: SessionStore, coordinator: TranslationCoordinator,
        receive: @escaping @MainActor (TranscriptEvent) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                while let event = try await subscription.next() { receive(event) }
            } catch {
                self?.recordFailure(error, run: run, store: store, coordinator: coordinator)
            }
            await subscription.cancel()
        }
    }

    private func recordFailure(
        _ error: any Error, run: UUID, store: SessionStore, coordinator: TranslationCoordinator
    ) {
        guard runID == run, runFailure == nil else { return }
        runFailure = error
        lastError = error as? TranscriptEventHub.Failure == .overflow
            ? "字幕の処理が追いつかないため録音を停止しました。最後の発話が欠けている可能性があります。"
            : "文字起こし中にエラーが発生しました: \(error.localizedDescription)"
        if store.phase == .listening {
            // 結果タスク自身からstopの完了を待つと自己待ちになるため、終了を別タスクで開始する。
            Task { [weak self] in
                guard let self, self.runID == run else { return }
                await self.stop(store: store, coordinator: coordinator)
            }
        }
    }

    private func finishEvents(store: SessionStore, coordinator: TranslationCoordinator) async {
        await hub?.finish()
        for consumer in consumers { await consumer.value }
        consumers = []
        await adapter?.finish()
        adapter = nil
        hub = nil
        normalizer = nil
        // イベント配信開始前から保留されていた翻訳単位も確定する。
        if let unit = store.flushBuffer() { coordinator.enqueue(id: unit.id, text: unit.english) }
        store.updateVolatile("")
        meetingStore.clearPartials()
    }
}

extension SessionController {
    private func startSelected(store: SessionStore, coordinator: TranslationCoordinator, locale: Locale,
                               glossary: [KeywordParser.GlossaryEntry], fastResults: Bool,
                               recognitionMode: SpeechRecognitionMode, selection: AudioInputSelection) async {
        if dual == nil {
            dual = DualTranscriptionController(microphone: audioSource, microphoneSpeech: speechService,
                timeline: timeline, activity: activity, owner: .conference, prepareModel: { $0 })
        }
        guard let dual else { return }
        usingDual = true
        lastError = nil
        store.setActiveGlossary(glossary)
        dual.phaseChanged = { phase in
            store.phase = phase
            if phase == .listening { store.markSessionStarted() }
        }
        dual.prepareOptionalConsumer = { [weak self, weak dual] hub in
            guard let self, let dual else { return }
            let adapter = LegacyTranslationAdapter(sessionID: dual.store.sessionID, store: store,
                coordinator: coordinator, origins: selection.origins, commonTimeline: true)
            self.adapter = adapter
            let subscription = await hub.subscribe()
            self.consumers = [Task {
                do {
                    while let event = try await subscription.next() { adapter.receive(event) }
                } catch {
                    self.lastError = "字幕処理が追いつかないため入力を停止します。"
                    Task { await dual.stop() }
                }
                await subscription.cancel()
            }]
        }
        dual.finishOptionalConsumer = { [weak self] in
            await self?.finishEvents(store: store, coordinator: coordinator)
        }
        await dual.start(microphoneLocale: locale, systemLocale: locale, fastResults: fastResults,
            recognitionMode: recognitionMode, contextKeywords: [.microphone: glossary.map(\.term), .systemAudio: glossary.map(\.term)], selection: selection)
    }
}
