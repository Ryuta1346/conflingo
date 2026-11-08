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

    private(set) var phase: SessionPhase = .idle
    private(set) var lastError: String?
    private(set) var preparation = ""
    private(set) var permissions: [AudioOrigin: AudioPermissionStatus] = [:]
    private(set) var startedInputs: Set<AudioOrigin> = []
    let store: MeetingSessionStore
    let activity: AudioInputUse

    private let inputs: [Input]
    private let timeline: MeetingTimeline
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

    init(
        microphone: any AudioSource = MicrophoneAudioSource(),
        systemAudio: any AudioSource = SystemAudioSource(),
        microphoneSpeech: (any SpeechTranscribing)? = nil,
        systemSpeech: (any SpeechTranscribing)? = nil,
        timeline: MeetingTimeline = MeetingTimeline(),
        activity: AudioInputUse = AudioInputUse(),
        prepareModel: @escaping @MainActor (Locale) async throws -> Locale = ModelAvailabilityService.prepareForTranscription
    ) {
        inputs = [
            Input(source: microphone, speech: microphoneSpeech ?? SpeechTranscriptionService(audioSource: microphone)),
            Input(source: systemAudio, speech: systemSpeech ?? SpeechTranscriptionService(audioSource: systemAudio))
        ]
        self.timeline = timeline
        self.activity = activity
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
        systemLocale: Locale = Locale(identifier: "en-US"), fastResults: Bool = false
    ) async {
        guard phase == .idle, !Task.isCancelled else { return }
        guard let token = activity.acquire(.dualTranscription) else {
            lastError = activity.busyMessage
            return
        }
        usageToken = token
        let run = UUID()
        runID = run
        failed = false
        lastError = nil
        phase = .preparing
        let task = Task {
            await prepareAndStart(
                run: run, locales: [.microphone: microphoneLocale, .systemAudio: systemLocale],
                fastResults: fastResults
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
        let pendingStart = startTask
        pendingStart?.cancel()
        let task = Task {
            await pendingStart?.value
            await finishInputs()
            runID = nil
            await hub?.finish()
            await consumer?.value
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
            }
            stopTask = nil
        }
        stopTask = task
        await task.value
    }

    func clear() {
        guard phase == .idle else { return }
        timeline.reset()
        store.reset(sessionID: timeline.sessionID)
        lastError = nil
    }

    private func prepareAndStart(run: UUID, locales: [AudioOrigin: Locale], fastResults: Bool) async {
        var currentOrigin = AudioOrigin.microphone
        do {
            var prepared: [AudioOrigin: Locale] = [:]
            for input in inputs {
                currentOrigin = input.origin
                try Task.checkCancellation()
                preparation = "\(input.origin.label)：認識モデルを準備中（必要に応じてダウンロード）"
                prepared[input.origin] = try await prepareModel(locales[input.origin] ?? Locale(identifier: "en-US"))
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
                    while let event = try await subscription.next() { self?.store.receive(event) }
                } catch {
                    self?.recordFailure(error, origin: nil, run: run)
                }
                await subscription.cancel()
            }
            for input in inputs {
                currentOrigin = input.origin
                try Task.checkCancellation()
                guard !failed, phase == .preparing else { throw CancellationError() }
                let locale = prepared[input.origin] ?? Locale(identifier: "en-US")
                preparation = "\(input.origin.label)：入力を開始中"
                activeInputs.insert(input.origin)
                try await input.speech.start(
                    locale: locale, contextKeywords: [], fastResults: fastResults,
                    onInputStarted: { [weak self] in
                        guard let self, self.runID == run, self.phase == .preparing else { return }
                        self.startedInputs.insert(input.origin)
                        self.normalizers[input.origin] = TranscriptEventNormalizer(
                            sessionID: self.timeline.sessionID, origin: input.origin,
                            languageCode: locale.identifier, inputOffset: self.timeline.beginInput()
                        )
                    },
                    receive: { [weak self] result in
                        guard let self, self.runID == run,
                              let event = self.normalizers[input.origin]?.makeEvent(result, receivedOffset: self.timeline.offset)
                        else { return }
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
                    return true
                } catch {
                    lastError = "\(input.origin.label)：停止を完了できませんでした。停止を再試行してください: \(error.localizedDescription)"
                    await input.speech.cancelRecognition()
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
                do { try await input.speech.finishRecognition() } catch {
                    if lastError == nil { lastError = "\(input.origin.label)：認識の終了に失敗しました: \(error.localizedDescription)" }
                    await input.speech.cancelRecognition()
                }
                activeInputs.remove(input.origin)
            }
        }
        for task in finishes { await task.value }
    }

    private func recordFailure(_ error: any Error, origin: AudioOrigin?, run: UUID) {
        guard runID == run, !failed else { return }
        failed = true
        let prefix = origin.map { "\($0.label)：" } ?? ""
        lastError = error as? TranscriptEventHub.Failure == .overflow
            ? "\(prefix)字幕の処理が追いつかないため入力を停止します。最後の発話が欠けている可能性があります。"
            : "\(prefix)文字起こしを継続できません: \(error.localizedDescription)"
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
