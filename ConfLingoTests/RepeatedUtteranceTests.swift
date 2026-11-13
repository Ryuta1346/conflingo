import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepeatedUtteranceTests {
    @Test(arguments: ["Yes.", "はい。"], [AudioOrigin.microphone, .systemAudio])
    func distinctEventsTranslateOnceEachAndSurviveSave(text: String, origin: AudioOrigin) async throws {
        let session = UUID()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator, origins: [origin])
        var normalizer = TranscriptEventNormalizer(sessionID: session, origin: origin, languageCode: "ja-JP", inputOffset: 10)
        for time in [1.0, 5.0] {
            let result = normalizer.makeEvent(
                SpeechResult(text: text, isFinal: true, startTime: time, endTime: time + 1), receivedOffset: time + 11)
            let event = try #require(result)
            adapter.receive(event)
            adapter.receive(event)
        }
        await adapter.finish()
        coordinator.finish()
        var queued: [TranslationCoordinator.PendingItem] = []
        for await item in stream { queued.append(item) }
        #expect(queued.map(\.text) == [text, text])
        #expect(Set(queued.map(\.id)).count == 2)
        #expect(queued.map(\.id) == store.units.map(\.id))
        #expect(store.units.map(\.segmentIDs) == store.segments.map { [$0.id] })
        #expect(store.segments.map(\.sessionOffset) == [11, 15])
        #expect(store.segments.map(\.languageCode) == ["ja-JP", "ja-JP"])
        #expect(TranscriptPresentation.source(store).map(\.text) == [text, text])
        for (index, item) in queued.enumerated() {
            store.applyTranslation(id: item.id, japanese: "訳文\(index + 1)")
        }
        #expect(TranscriptPresentation.translation(store).map(\.text) == ["訳文1", "訳文2"])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for target in [nil, "en"] as [String?] {
            let snapshot = SessionSnapshot.conference(ConferenceSnapshot(
                id: store.sessionID, title: "Repeated utterances", startedAt: nil,
                sourceLanguage: "ja-JP", targetLanguage: target, segments: store.segments, units: store.units))
            try await SessionFiles(directory: root).save(snapshot)
            let loaded = try await SessionFiles(directory: root).load(store.sessionID)
            #expect(loaded.snapshot == snapshot)
            let markdown = loaded.snapshot.markdown
            #expect(markdown.contains("### Segment 1 [00:00:01]"))
            #expect(markdown.contains("### Segment 2 [00:00:05]"))
            #expect(markdown.components(separatedBy: "English:\n" + text).count - 1 == 2)
            if target != nil {
                #expect(markdown.contains("Japanese:\n訳文1"))
                #expect(markdown.contains("Japanese:\n訳文2"))
            }
        }
    }

    @Test func repeatedFragmentsFlushTogetherOnlyOnce() async {
        let session = UUID()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator)
        adapter.receive(transcriptEvent(sessionID: session, text: "again"))
        adapter.receive(transcriptEvent(sessionID: session, text: "again"))
        #expect(store.units.isEmpty)
        await adapter.finish()
        await adapter.finish()
        coordinator.finish()
        var queued: [TranslationCoordinator.PendingItem] = []
        for await item in stream { queued.append(item) }
        #expect(store.segments.count == 2)
        #expect(queued.map(\.text) == ["again again"])
        #expect(store.units.map(\.segmentIDs) == [store.segments.map(\.id)])
        #expect(store.bufferedSegmentIDs.isEmpty)
    }

    @Test(arguments: [AudioInputSelection.microphone, .systemAudio, .both])
    func selectedInputsRetainRepeatsAcrossRestartAndClear(selection: AudioInputSelection) async throws {
        let fixture = DualFixture()
        let controller = SessionController(dualController: fixture.controller(
            timeline: MeetingTimeline(now: { 0 }), owner: .conference))
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let session = store.sessionID
        let input = selection == .systemAudio ? fixture.system : fixture.microphone
        for _ in 0..<2 {
            await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "en"), selection: selection)
            #expect(store.phase == .listening)
            try await input.emit("Yes.", time: 1)
            try await input.emit("Yes.", time: 5)
            await controller.stop(store: store, coordinator: coordinator)
            #expect(store.phase == .idle)
        }
        #expect(store.sessionID == session)
        #expect(store.segments.map(\.english) == Array(repeating: "Yes.", count: 4))
        #expect(Set(store.segments.map(\.id)).count == 4)
        #expect(store.units.count == 4)
        #expect(store.segments.map(\.startTime) == [1, 5, 1, 5])
        controller.reset(store: store)
        #expect(store.sessionID != session)
        #expect(store.segments.isEmpty)
        #expect(store.units.isEmpty)
        await controller.start(store: store, coordinator: coordinator, locale: Locale(identifier: "en"), selection: selection)
        try await input.emit("Yes.", time: 1)
        if selection == .both { try await fixture.system.emit("Yes.", time: 2) }
        await controller.stop(store: store, coordinator: coordinator)
        #expect(store.segments.map(\.english) == Array(repeating: "Yes.", count: selection == .both ? 2 : 1))
        #expect(Set(store.segments.compactMap(\.origin)) == selection.origins)
        #expect(store.units.count == (selection == .both ? 2 : 1))
    }
}
