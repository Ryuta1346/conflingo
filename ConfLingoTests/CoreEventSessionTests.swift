import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CoreEventSessionTests {
    @Test func translationPreparationFailureAndRetryKeepSpeechRunning() async throws {
        let speech = StubSpeechInput()
        let store = SessionStore()
        store.mode = .translation
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        let generation = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: generation, reason: "download cancelled")
        try await speech.emit(text: "Speech during failure.")
        let retry = coordinator.beginPreparation()
        try await speech.emit(text: "Speech during retry.")
        let stream = try #require(coordinator.prepared(generation: retry, store: store))
        try await speech.emit(text: "Speech after recovery.")
        #expect(store.phase == .listening)
        #expect(controller.lastError == nil)
        #expect(speech.starts == 1)
        #expect(speech.stops == 0)
        // StopでEvent Hubをdrainし、認識の非同期配送をすべて待つ。
        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()
        var items: [String] = []
        for await item in stream { items.append(item.text) }
        #expect(items == ["Speech during failure.", "Speech during retry.", "Speech after recovery."])
        #expect(store.segments.map(\.english) == items)
    }

    @Test func injectedSourceControlsSessionPermissionWithoutOpeningDeniedInput() async {
        let permission = StubMicrophonePermission(status: .undetermined)
        permission.decision = false
        let capture = StubAudioCapture()
        let source = permission.source(capture: capture)
        let speech = StubSpeechInput()
        let controller = SessionController(audioSource: source, speechService: speech)
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(permission.requests == 1)
        #expect(source.permissionStatus == .denied)
        #expect(speech.starts == 0)
        #expect(capture.starts == 0)
        #expect(store.phase == .idle)
        #expect(controller.lastError != nil)
    }

    @Test func cancelledPermissionWaitDoesNotStartSessionAndRetryCanStart() async {
        let permission = StubMicrophonePermission(status: .undetermined)
        permission.hold = true
        let source = permission.source(capture: StubAudioCapture())
        let speech = StubSpeechInput()
        let controller = SessionController(audioSource: source, speechService: speech)
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let start = Task { await controller.start(store: store, coordinator: coordinator, locale: .current) }
        var prompted = permission.prompted.stream.makeAsyncIterator()
        _ = await prompted.next()
        // 準備中の二重開始も、権限要求や認識を追加しない。
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        start.cancel()
        permission.release.continuation.yield(())
        await start.value
        #expect(store.phase == .idle)
        #expect(controller.lastError == nil)
        #expect(speech.starts == 0)
        #expect(permission.requests == 1)
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(store.phase == .listening)
        #expect(speech.starts == 1)
        #expect(permission.requests == 1)
        await controller.stop(store: store, coordinator: coordinator)
    }

    @Test func glossaryIsReadyWhenInputBegins() async {
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let glossary = [KeywordParser.GlossaryEntry(term: "API", target: "エーピーアイ")]
        speech.inputStarted = { #expect(store.activeGlossary == glossary) }
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current, glossary: glossary)
        await controller.stop(store: store, coordinator: coordinator)
    }

    @Test func requiredSubscriptionFailureAutomaticallyStopsAndCanBeAwaited() async throws {
        let speech = StubSpeechInput()
        speech.holdStop = true
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        try await speech.emit(text: "accepted")
        speech.fail(TranscriptEventHub.Failure.overflow)
        var stopping = speech.stopSignal.stream.makeAsyncIterator()
        _ = await stopping.next()
        speech.releaseStop()
        await controller.stop(store: store, coordinator: coordinator)
        #expect(store.phase == .idle)
        #expect(speech.stops == 1)
        #expect(store.units.map(\.english) == ["accepted"])
        #expect(controller.lastError?.contains("処理が追いつかない") == true)
    }

    @Test func stopDrainsLastRecognitionBeforeFlushingTranslation() async throws {
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let translations = coordinator.attach()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "en-US"))
        try await speech.emit(text: "an unfinished", isFinal: false)
        speech.stopResults = [SpeechResult(text: "an unfinished sentence", isFinal: true, startTime: 1, endTime: 2)]
        await controller.stop(store: store, coordinator: coordinator)
        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()
        var items: [String] = []
        for await item in translations { items.append(item.text) }
        #expect(items == ["an unfinished sentence"])
        #expect(controller.meetingStore.finals.map(\.text) == items)
        #expect(controller.meetingStore.partials.isEmpty)
        #expect(store.volatileText.isEmpty)
        #expect(store.phase == .idle)
        #expect(speech.stops == 1)
    }

    @Test func resumeKeepsTimelineAndClearRejectsOldResults() async throws {
        var now = 100.0
        let timeline = MeetingTimeline(now: { now })
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true }, timeline: timeline)
        await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "en-US"))
        try await speech.emit(text: "first.")
        let oldReceive = try #require(speech.receive)
        await controller.stop(store: store, coordinator: coordinator)
        let sessionID = controller.meetingStore.sessionID
        now = 125
        await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "ja-JP"))
        try await speech.emit(text: "次です。")
        await controller.stop(store: store, coordinator: coordinator)
        #expect(controller.meetingStore.sessionID == sessionID)
        #expect(controller.meetingStore.finals.map(\.startOffset) == [1, 26])
        #expect(controller.meetingStore.finals.map(\.languageCode) == ["en-US", "ja-JP"])
        #expect(store.segments.map(\.startTime) == [1, 1])
        controller.reset(store: store)
        #expect(controller.meetingStore.sessionID != sessionID)
        await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "en-US"))
        try await oldReceive(SpeechResult(text: "stale", isFinal: true, startTime: 1, endTime: 2))
        try await speech.emit(text: "new.")
        await controller.stop(store: store, coordinator: coordinator)
        #expect(controller.meetingStore.finals.map(\.text) == ["new."])
        #expect(controller.meetingStore.finals.first?.startOffset == 1)
        #expect(store.segments.map(\.english) == ["new."])
    }

    @Test func deniedPermissionNeverStartsInput() async {
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { false })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(speech.starts == 0)
        #expect(store.phase == .idle)
        #expect(controller.lastError != nil)
    }

    @Test func failedStartCleansUpAndCanRetry() async throws {
        let speech = StubSpeechInput()
        speech.startError = StubSpeechInput.Failure.start
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(store.phase == .idle)
        #expect(speech.stops == 1)
        #expect(controller.lastError != nil)
        speech.startError = nil
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        try await speech.emit(text: "retry.")
        await controller.stop(store: store, coordinator: coordinator)
        #expect(controller.lastError == nil)
        #expect(store.segments.map(\.english) == ["retry."])
    }

    @Test func recognitionFailureAndStopFailureStillDrainAcceptedFinals() async throws {
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        try await speech.emit(text: "accepted")
        speech.stopError = StubSpeechInput.Failure.stop
        speech.fail(StubSpeechInput.Failure.recognition)
        await controller.stop(store: store, coordinator: coordinator)
        #expect(store.phase == .idle)
        #expect(store.units.map(\.english) == ["accepted"])
        #expect(controller.lastError != nil)
    }

    @Test func failureDuringStartupDoesNotEnterListening() async {
        let speech = StubSpeechInput()
        speech.failDuringStart = true
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(store.phase == .idle)
        #expect(speech.stops == 1)
        #expect(controller.lastError != nil)
    }

    @Test func resetAndSecondStartAreIgnoredWhileListening() async throws {
        let speech = StubSpeechInput()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(speechService: speech, requestPermission: { true })
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        let session = controller.meetingStore.sessionID
        controller.reset(store: store)
        await controller.start(store: store, coordinator: coordinator, locale: .current)
        #expect(speech.starts == 1)
        #expect(controller.meetingStore.sessionID == session)
        try await speech.emit(text: "kept.")
        await controller.stop(store: store, coordinator: coordinator)
        #expect(store.segments.map(\.english) == ["kept."])
    }
}

@MainActor
private final class StubSpeechInput: SpeechTranscribing {
    enum Failure: Error { case start, stop, recognition }
    var starts = 0
    var stops = 0
    var startError: (any Error)?
    var stopError: (any Error)?
    var failDuringStart = false
    var inputStarted: (() -> Void)?
    var holdStop = false
    let stopSignal = AsyncStream<Void>.makeStream()
    private let stopGate = AsyncStream<Void>.makeStream()
    var stopResults: [SpeechResult] = []
    var receive: (@MainActor (SpeechResult) async throws -> Void)?
    private var onFailure: (@MainActor (any Error) -> Void)?

    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        starts += 1
        self.receive = receive
        self.onFailure = onFailure
        if let startError { throw startError }
        onInputStarted()
        inputStarted?()
        if failDuringStart { onFailure(Failure.recognition) }
    }

    func emit(text: String, isFinal: Bool = true) async throws {
        try await receive?(SpeechResult(text: text, isFinal: isFinal, startTime: 1, endTime: 2))
    }

    func fail(_ error: any Error) { onFailure?(error) }

    func releaseStop() { stopGate.continuation.yield(()) }

    func stopInput() async throws {}
    func finishRecognition() async throws { try await stop() }
    func cancelRecognition() async {}

    func stop() async throws {
        stops += 1
        stopSignal.continuation.yield(())
        if holdStop {
            for await _ in stopGate.stream { break }
        }
        for result in stopResults { try await receive?(result) }
        stopResults = []
        if let stopError { throw stopError }
    }
}
