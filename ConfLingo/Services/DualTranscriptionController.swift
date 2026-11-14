import Foundation
import Observation

@MainActor
@Observable
final class DualTranscriptionController {
    @MainActor private struct Input {
        let source: any AudioSource
        let speech: any SpeechTranscribing
        var origin: AudioOrigin { source.origin }
    }

    private(set) var phase: SessionPhase = .idle { didSet { phaseChanged?(phase) } }
    private(set) var lastError: String?
    private(set) var preparation = ""
    private(set) var permissions: [AudioOrigin: AudioPermissionStatus] = [:]
    private(set) var startedInputs: Set<AudioOrigin> = []
    private(set) var startedAt: Date?
    let store: MeetingSessionStore
    let activity: AudioInputUse
    var prepareOptionalConsumer: (@MainActor (TranscriptEventHub) async -> Void)?
    var finishOptionalConsumer: (@MainActor () async -> Void)?
    var captureActivityChanged: (@MainActor (Bool) -> Void)?
    var elapsedOffset: TimeInterval { timeline.offset }
    var isStopping: Bool { stopTask != nil }

    let diagnostics: AudioDiagnostics?
    private(set) var diagnosticSaveFailed = false
    private let inputs: [Input]
    private var selectedOrigins: Set<AudioOrigin> = [.microphone, .systemAudio]
    var phaseChanged: ((SessionPhase) -> Void)?
    private let timeline: MeetingTimeline
    private let owner: AudioInputUse.Owner
    private let prepareModel: @MainActor (Locale) async throws -> Locale
    private var usageToken: UUID?
    private var runID: UUID?
    private var failed = false
    private var activeInputs: Set<AudioOrigin> = []
    private var normalizers: [AudioOrigin: TranscriptEventNormalizer] = [:]
    private var hub: TranscriptEventHub?
    private var consumer: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var contextTask: Task<Bool, Never>?
    private var contextUpdateID: UUID?
    private var stopFailureMessage: String?

    init(
        microphone: (any AudioSource)? = nil,
        systemAudio: any AudioSource = SystemAudioSource(),
        microphoneSpeech: (any SpeechTranscribing)? = nil,
        systemSpeech: (any SpeechTranscribing)? = nil,
        timeline: MeetingTimeline = MeetingTimeline(),
        activity: AudioInputUse = AudioInputUse(),
        owner: AudioInputUse.Owner = .dualTranscription,
        diagnostics: AudioDiagnostics? = AudioDiagnostics.fromEnvironment(),
        prepareModel: @escaping @MainActor (Locale) async throws -> Locale = ModelAvailabilityService.prepareForTranscription
    ) {
        self.diagnostics = diagnostics
        let microphone = microphone ?? MicrophoneAudioSource(capture: AudioCaptureService(diagnostics: diagnostics))
        inputs = [
            Input(source: microphone, speech: microphoneSpeech ?? SpeechTranscriptionService(audioSource: microphone, diagnostics: diagnostics)),
            Input(source: systemAudio, speech: systemSpeech ?? SpeechTranscriptionService(audioSource: systemAudio, diagnostics: diagnostics))
        ]
        self.timeline = timeline
        self.activity = activity
        self.owner = owner
        self.prepareModel = prepareModel
        store = MeetingSessionStore(sessionID: timeline.sessionID)
        refreshPermissions()
    }

    func refreshPermissions() {
        for input in inputs { permissions[input.origin] = input.source.permissionStatus }
    }

    func inputState(_ origin: AudioOrigin) -> AudioSourceState {
        guard activeInputs.contains(origin) else { return .idle }
        if phase == .stopping { return .stopping }
        return startedInputs.contains(origin) ? .running : .starting
    }

    func start(
        microphoneLocale: Locale = Locale(identifier: "en-US"),
        systemLocale: Locale = Locale(identifier: "en-US"), fastResults: Bool = false,
        recognitionMode: SpeechRecognitionMode = .standard, contextKeywords: [AudioOrigin: [String]] = [:],
        selection: AudioInputSelection = .both
    ) async {
        guard phase == .idle, !Task.isCancelled else { return }
        guard let token = activity.acquire(owner) else {
            lastError = activity.busyMessage
            return
        }
        usageToken = token
        selectedOrigins = selection.origins
        diagnostics?.begin()
        diagnosticSaveFailed = false
        let run = UUID()
        runID = run
        failed = false
        lastError = nil
        stopFailureMessage = nil
        phase = .preparing
        let task = Task {
            await prepareAndStart(
                run: run, locales: [.microphone: microphoneLocale, .systemAudio: systemLocale],
                fastResults: fastResults, recognitionMode: recognitionMode, contextKeywords: contextKeywords
            )
            startTask = nil
        }
        startTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard runID == run else { return }
        if failed || Task.isCancelled || phase != .listening { await stop() }
    }

    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard phase != .idle else { return }
        phase = .stopping
        diagnostics?.mark(.stopStarted)
        captureActivityChanged?(false)
        let pendingContext = contextTask
        pendingContext?.cancel()
        let pendingStart = startTask
        pendingStart?.cancel()
        let task = Task {
            await pendingStart?.value
            if let stopFailureMessage, lastError == stopFailureMessage { lastError = nil }
            stopFailureMessage = nil
            await finishInputs()
            // Stop capture first, then drain context writes before allowing another run.
            _ = await pendingContext?.value
            runID = nil
            await hub?.finish()
            await consumer?.value
            await finishOptionalConsumer?()
            diagnostics?.mark(.deliveryFinished)
            hub = nil
            consumer = nil
            normalizers = [:]
            startedInputs = []
            store.clearPartials()
            preparation = ""
            if activeInputs.isEmpty {
                activity.release(usageToken)
                usageToken = nil
                phase = .idle
                diagnostics?.finish()
                do { try diagnostics?.saveIfRequested() } catch { diagnosticSaveFailed = true }
            }
            stopTask = nil
        }
        stopTask = task
        await task.value
    }

    func clear() {
        guard phase == .idle else { return }
        timeline.reset()
        startedAt = nil
        store.reset(sessionID: timeline.sessionID)
        lastError = nil
    }

    func updateContext(_ keywords: [AudioOrigin: [String]]) async -> Bool {
        guard phase == .listening, let run = runID, !Task.isCancelled else { return false }
        let previous = contextTask
        previous?.cancel()
        let id = UUID()
        contextUpdateID = id
        let task = Task {
            _ = await previous?.value
            var succeeded = true
            for input in inputs where activeInputs.contains(input.origin) {
                guard runID == run, phase == .listening, !Task.isCancelled else { return false }
                do { try await input.speech.updateContext(keywords[input.origin] ?? []) }
                catch { succeeded = false }
            }
            return succeeded && runID == run && phase == .listening && !Task.isCancelled
        }
        contextTask = task
        let result = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if contextUpdateID == id { contextTask = nil; contextUpdateID = nil }
        return result
    }

    private func prepareAndStart(run: UUID, locales: [AudioOrigin: Locale], fastResults: Bool,
                                 recognitionMode: SpeechRecognitionMode, contextKeywords: [AudioOrigin: [String]]) async {
        var currentOrigin = AudioOrigin.microphone
        do {
            var prepared: [AudioOrigin: Locale] = [:]
            for input in inputs where selectedOrigins.contains(input.origin) {
                currentOrigin = input.origin
                try Task.checkCancellation()
                preparation = "\(input.origin.label)：認識モデルを準備中（必要に応じてダウンロード）"
                let locale = locales[input.origin] ?? Locale(identifier: "en-US")
                prepared[input.origin] = recognitionMode == .standard ? try await prepareModel(locale) : locale
                try await input.speech.prepare(mode: recognitionMode, locale: prepared[input.origin] ?? locale)
                try Task.checkCancellation()
                preparation = "\(input.origin.label)：アクセスを確認中"
                let allowed = await input.source.requestPermission()
                refreshPermissions()
                try Task.checkCancellation()
                guard allowed else { throw AudioSourceError.permissionDenied }
            }
            let hub = TranscriptEventHub()
            self.hub = hub
            let subscription = await hub.subscribe()
            consumer = Task { [weak self] in
                do {
                    while let event = try await subscription.next() {
                        guard let self else { break }
                        let accepted = self.store.receive(event)
                        self.diagnostics?.record(accepted ? .storeAccepted : .storeRejected, origin: event.origin)
                    }
                } catch {
                    self?.recordFailure(error, origin: nil, run: run)
                }
                await subscription.cancel()
            }
            await prepareOptionalConsumer?(hub)
            for input in inputs where selectedOrigins.contains(input.origin) {
                currentOrigin = input.origin
                try Task.checkCancellation()
                guard !failed, phase == .preparing else { throw CancellationError() }
                let locale = prepared[input.origin] ?? Locale(identifier: "en-US")
                preparation = "\(input.origin.label)：入力を開始中"
                activeInputs.insert(input.origin)
                try await input.speech.start(
                    locale: locale, contextKeywords: contextKeywords[input.origin] ?? [], fastResults: fastResults,
                    onInputStarted: { [weak self] in
                        guard let self, self.runID == run, self.phase == .preparing else { return }
                        self.startedInputs.insert(input.origin)
                        if self.startedAt == nil { self.startedAt = Date() }
                        self.normalizers[input.origin] = TranscriptEventNormalizer(
                            sessionID: self.timeline.sessionID, origin: input.origin,
                            languageCode: locale.identifier, inputOffset: self.timeline.beginInput()
                        )
                    },
                    receive: { [weak self] result in
                        guard let self, self.runID == run else { return }
                        self.diagnostics?.record(result.isFinal ? .finalResult : .partialResult, origin: input.origin)
                        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.diagnostics?.record(.emptyResult, origin: input.origin)
                        }
                        guard let event = self.normalizers[input.origin]?.makeEvent(result, receivedOffset: self.timeline.offset) else {
                            self.diagnostics?.record(.normalizationRejected, origin: input.origin)
                            return
                        }
                        self.diagnostics?.record(.normalized, origin: input.origin)
                        let failed = try await hub.publish(event)
                        if failed.contains(subscription.id) { throw TranscriptEventHub.Failure.overflow }
                    },
                    onFailure: { [weak self] error in
                        self?.recordFailure(error, origin: input.origin, run: run)
                    }
                )
            }
            try Task.checkCancellation()
            guard !failed, phase == .preparing else { throw CancellationError() }
            preparation = ""
            phase = .listening
            captureActivityChanged?(true)
        } catch {
            if !(error is CancellationError) { recordFailure(error, origin: currentOrigin, run: run) }
        }
    }

    private func finishInputs() async {
        let pending = inputs.filter { activeInputs.contains($0.origin) }
        // Create every stop before awaiting any of them; recognition finalization comes later.
        let stops = pending.map { input in
            Task { () -> Bool in
                do {
                    try await input.speech.stopInput()
                    diagnostics?.record(.inputStopped, origin: input.origin)
                    return true
                } catch {
                    let message = "\(input.origin.label)：停止を完了できませんでした。停止を再試行してください: \(error.localizedDescription)"
                    stopFailureMessage = message
                    lastError = message
                    await input.speech.cancelRecognition()
                    diagnostics?.record(.recognitionCancelled, origin: input.origin)
                    return false
                }
            }
        }
        var stopped: [Input] = []
        for (input, task) in zip(pending, stops) {
            if await task.value { stopped.append(input) }
        }
        let finishes = stopped.map { input in
            Task {
                do {
                    try await input.speech.finishRecognition()
                    diagnostics?.record(.recognitionFinished, origin: input.origin)
                } catch {
                    if lastError == nil { lastError = "\(input.origin.label)：認識の終了に失敗しました: \(error.localizedDescription)" }
                    await input.speech.cancelRecognition()
                    diagnostics?.record(.recognitionCancelled, origin: input.origin)
                }
                activeInputs.remove(input.origin)
            }
        }
        for task in finishes { await task.value }
    }

    private func recordFailure(_ error: any Error, origin: AudioOrigin?, run: UUID) {
        guard runID == run, !failed else { return }
        failed = true
        captureActivityChanged?(false)
        let prefix = origin.map { "\($0.label)：" } ?? ""
        if origin == .microphone, error as? AudioSourceError == .permissionDenied {
            lastError = "マイクへのアクセスが許可されていません。システム設定 > プライバシーとセキュリティ > マイク で ConfLingo を許可してください。"
        } else {
            lastError = error as? TranscriptEventHub.Failure == .overflow
                ? "\(prefix)字幕の処理が追いつかないため入力を停止します。最後の発話が欠けている可能性があります。"
                : "\(prefix)文字起こしを継続できません: \(error.localizedDescription)"
        }
        // A result callback must return before stop waits for the recognition task.
        Task { [weak self] in
            guard let self, self.runID == run, self.phase != .stopping else { return }
            await self.stop()
        }
    }
}

extension AudioOrigin {
    var label: String {
        switch self {
        case .microphone: "マイク"
        case .systemAudio: "内部音声"
        }
    }
}
