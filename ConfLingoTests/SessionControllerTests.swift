import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ConferenceUnifiedInputTests {
    @Test(arguments: [AudioInputSelection.microphone, .systemAudio, .both])
    func selectedInputsDeliverCaptionsBeforeAndAfterClear(selection: AudioInputSelection) async throws {
        let fixture = DualFixture()
        fixture.microphonePermission.status = .undetermined
        var systemRequests = 0
        let systemSource = SystemAudioSource(capture: StubSystemCapture(), permissionStatus: { .unknown }, requestPermission: {
            systemRequests += 1
            return true
        })
        let dual = DualTranscriptionController(
            microphone: fixture.microphonePermission.source(capture: StubAudioCapture()), systemAudio: systemSource,
            microphoneSpeech: fixture.microphone, systemSpeech: fixture.system,
            timeline: MeetingTimeline(now: { 0 }), activity: fixture.activity, owner: .conference,
            diagnostics: nil, prepareModel: { $0 })
        // 旧経路へ戻った場合も、実デバイスやOSの権限ダイアログには触れない。
        let deniedSource = StubMicrophonePermission(status: .denied).source(capture: StubAudioCapture())
        let controller = SessionController(audioSource: deniedSource, speechService: DualFakeSpeech(), dualController: dual)
        let store = SessionStore()
        let translation = TranslationCoordinator()
        for run in 1...2 {
            await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: selection)
            #expect(store.phase == .listening)
            #expect(fixture.activity.owner == .conference)
            if selection.origins.contains(.microphone) { try await fixture.microphone.emit("Microphone.", time: 1) }
            if selection.origins.contains(.systemAudio) { try await fixture.system.emit("System.", time: 2) }
            await controller.stop(store: store, coordinator: translation)
            #expect(Set(store.segments.compactMap(\.origin)) == selection.origins)
            #expect(Set(store.units.map(\.english)) == Set(selection.origins.map { $0 == .microphone ? "Microphone." : "System." }))
            #expect(fixture.microphone.starts == (selection.origins.contains(.microphone) ? run : 0))
            #expect(fixture.system.starts == (selection.origins.contains(.systemAudio) ? run : 0))
            #expect(store.phase == .idle)
            #expect(fixture.activity.owner == nil)
            controller.reset(store: store)
            #expect(store.segments.isEmpty)
        }
        #expect(fixture.microphonePermission.requests == (selection.origins.contains(.microphone) ? 1 : 0))
        #expect(systemRequests == (selection.origins.contains(.systemAudio) ? 2 : 0))
    }

    @Test func switchingInputsKeepsCaptionAndSupportTimesIndependentOfPastSelection() async throws {
        let fixture = DualFixture()
        var now = 100.0
        let controller = SessionController(dualController: fixture.controller(
            timeline: MeetingTimeline(now: { now }), owner: .conference))
        let store = SessionStore()
        let translation = TranslationCoordinator()
        let sessionID = store.sessionID
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: .systemAudio)
        try await fixture.system.emit("System first.", time: 2)
        await controller.stop(store: store, coordinator: translation)
        now = 125
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "ja"))
        try await fixture.microphone.emit("マイク再開。", time: 1)
        await controller.stop(store: store, coordinator: translation)
        now = 150
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: .both)
        try await fixture.microphone.emit("Both microphone.", time: 1)
        try await fixture.system.emit("Both system.", time: 2)
        await controller.stop(store: store, coordinator: translation)
        #expect(store.sessionID == sessionID)
        #expect(store.segments.map(\.startTime) == [2, 1, 51, 52])
        #expect(store.units.map(\.startTime) == [2, 1, 51, 52])
        #expect(store.segments.map(\.sessionOffset) == [2, 26, 51, 52])
        #expect(store.segments.map(\.languageCode) == ["en", "ja", "en", "en"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        for targetLanguage in [nil, "ja"] as [String?] {
            let snapshot = SessionSnapshot.conference(ConferenceSnapshot(
                id: store.sessionID, title: "Input switching", startedAt: store.startedAt,
                sourceLanguage: store.sourceLanguage, targetLanguage: targetLanguage,
                segments: store.segments, units: store.units))
            try await files.save(snapshot)
            let restored = try await files.load(store.sessionID)
            #expect(restored.snapshot == snapshot)
            #expect(restored.snapshot.markdown.contains("### Segment 2 [00:00:01]"))
            #expect(restored.snapshot.markdown.contains("### Segment 3 [00:00:51]"))
            #expect(restored.snapshot.markdown.contains("マイク再開。"))
        }
        controller.reset(store: store)
        #expect(store.sessionID != sessionID)
        now = 200
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "ja"))
        try await fixture.microphone.emit("新規。", time: 1)
        await controller.stop(store: store, coordinator: translation)
        #expect(store.segments.map(\.startTime) == [1])
        #expect(store.segments.map(\.sessionOffset) == [1])
    }

    @Test(arguments: [AudioInputSelection.microphone, .systemAudio, .both])
    func settingsAndContextApplyOnlyToSelectedInputs(selection: AudioInputSelection) async {
        let fixture = DualFixture()
        let controller = SessionController(dualController: fixture.controller(owner: .conference))
        let store = SessionStore()
        let translation = TranslationCoordinator()
        let locale = Locale(identifier: "ja-JP")
        let glossary = [KeywordParser.GlossaryEntry(term: "ConfLingo", target: "コンフリンゴ")]
        fixture.microphone.beforeInput = { #expect(store.activeGlossary == glossary) }
        fixture.system.beforeInput = { #expect(store.activeGlossary == glossary) }
        await controller.start(store: store, coordinator: translation, locale: locale, glossary: glossary,
            fastResults: true, recognitionMode: .vocabulary, selection: selection)
        for (origin, input) in [(AudioOrigin.microphone, fixture.microphone), (.systemAudio, fixture.system)] {
            if selection.origins.contains(origin) {
                #expect(input.preparedMode == .vocabulary)
                #expect(input.startedLocale == locale)
                #expect(input.fastResults)
                #expect(input.keywords == ["ConfLingo"])
            } else {
                #expect(input.starts == 0)
                #expect(input.keywords.isEmpty)
            }
        }
        #expect(await controller.updateContext(["Updated"], store: store))
        #expect(fixture.microphone.keywords == (selection.origins.contains(.microphone) ? ["Updated"] : []))
        #expect(fixture.system.keywords == (selection.origins.contains(.systemAudio) ? ["Updated"] : []))
        let activeInput = selection == .systemAudio ? fixture.system : fixture.microphone
        activeInput.contextFails = true
        #expect(await controller.updateContext(["Failed"], store: store) == false)
        await controller.stop(store: store, coordinator: translation)
        #expect(await controller.updateContext(["Stopped"], store: store) == false)
    }

    @Test func stopDuringPreparationRejectsLateStartAndCanRestart() async {
        let fixture = DualFixture()
        let gate = TestGate()
        fixture.microphone.startGate = gate
        let controller = SessionController(dualController: fixture.controller(owner: .conference))
        let store = SessionStore()
        let translation = TranslationCoordinator()
        let start = Task { await controller.start(store: store, coordinator: translation, locale: .current) }
        await gate.entered.next()
        #expect(store.phase == .preparing)
        let stop = Task { await controller.stop(store: store, coordinator: translation) }
        await gate.cancelled.next()
        #expect(store.phase == .stopping)
        #expect(controller.isStopping)
        gate.release()
        await start.value
        await stop.value
        #expect(store.phase == .idle)
        #expect(store.startedAt == nil)
        #expect(!controller.isStopping)
        #expect(fixture.activity.owner == nil)
        #expect(fixture.system.starts == 0)
        fixture.microphone.startGate = nil
        await controller.start(store: store, coordinator: translation, locale: .current)
        #expect(store.phase == .listening)
        #expect(controller.lastError == nil)
        await controller.stop(store: store, coordinator: translation)
    }

    @Test func concurrentStopsWaitForLastRecognitionAndEnqueueItOnce() async throws {
        let fixture = DualFixture()
        let controller = SessionController(dualController: fixture.controller(owner: .conference))
        let store = SessionStore()
        let translation = TranslationCoordinator()
        let stream = translation.attach()
        await controller.start(store: store, coordinator: translation, locale: .current)
        try await fixture.microphone.emit("unfinished", time: 9, final: false)
        let gate = TestGate()
        fixture.microphone.finishGate = gate
        fixture.microphone.finalOnStop = "Last unfinished sentence"
        let first = Task { await controller.stop(store: store, coordinator: translation) }
        await gate.entered.next()
        let second = Task { await controller.stop(store: store, coordinator: translation) }
        #expect(controller.isStopping)
        #expect(store.phase == .stopping)
        #expect(fixture.microphone.inputStops == 1)
        gate.release()
        await first.value
        await second.value
        translation.finish()
        var texts: [String] = []
        for await item in stream { texts.append(item.text) }
        #expect(texts == ["Last unfinished sentence"])
        #expect(store.segments.map(\.english) == texts)
        #expect(store.volatileText.isEmpty)
        #expect(fixture.microphone.finishes == 1)
        #expect(!controller.isStopping)
        #expect(store.phase == .idle)
    }
}

@MainActor
struct SessionControllerTests {
    /// Stop 時、文末待ちのまま残ったバッファが翻訳単位として確定され翻訳キューに入ること。
    @Test func stopFlushesRemainingBufferedSegments() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let controller = SessionController(dualController: DualFixture().controller(owner: .conference))

        await controller.start(store: store, coordinator: coordinator, locale: .current)
        // 文末なしの確定済みセグメントをバッファに残す。
        let id = store.appendFinal("an unfinished segment without sentence end")!
        #expect(store.bufferSegment(id) == nil)

        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()

        #expect(store.phase == .idle)
        #expect(store.units.count == 1)
        #expect(store.bufferedSegmentIDs.isEmpty)
        var enqueued: [TranslationCoordinator.PendingItem] = []
        for await item in stream {
            enqueued.append(item)
        }
        #expect(enqueued.map(\.id) == [store.units[0].id])
    }

    /// Stop 時、バッファが空なら翻訳単位もキュー投入も発生しないこと。
    @Test func stopWithEmptyBufferDoesNotEnqueue() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let controller = SessionController(dualController: DualFixture().controller(owner: .conference))
        await controller.start(store: store, coordinator: coordinator, locale: .current)

        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()

        #expect(store.phase == .idle)
        #expect(store.units.isEmpty)
        var enqueued: [TranslationCoordinator.PendingItem] = []
        for await item in stream {
            enqueued.append(item)
        }
        #expect(enqueued.isEmpty)
    }

    /// idleでのStopは、開始前のバッファを確定しない。
    @Test func stopIsNoOpWhenNotListening() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController(dualController: DualFixture().controller(owner: .conference))
        let id = store.appendFinal("buffered text")!
        _ = store.bufferSegment(id)

        await controller.stop(store: store, coordinator: coordinator)

        #expect(store.phase == .idle)
        #expect(store.units.isEmpty)
        #expect(store.bufferedSegmentIDs.count == 1)
    }

    @Test func repeatedStopFlushesBufferedSegmentOnlyOnce() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let controller = SessionController(dualController: DualFixture().controller(owner: .conference))
        let id = store.appendFinal("an unfinished segment")!
        _ = store.bufferSegment(id)
        await controller.start(store: store, coordinator: coordinator, locale: .current)

        await controller.stop(store: store, coordinator: coordinator)
        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()

        var enqueued: [TranslationCoordinator.PendingItem] = []
        for await item in stream { enqueued.append(item) }
        #expect(store.phase == .idle)
        #expect(store.units.count == 1)
        #expect(enqueued.map(\.id) == store.units.map(\.id))
    }
}
