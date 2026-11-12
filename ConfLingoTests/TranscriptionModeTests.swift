import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct TranscriptionModeTests {
    @Test func conferenceResetDefaultsToTranscriptionAndNeedsNoTranslationModels() async {
        let store = SessionStore()
        #expect(store.mode == .transcription)
        let backend = PreparationStub()
        backend.failure = .translation
        let availability = ModelAvailabilityService(backend: backend)
        #expect(await availability.checkAndPrepare(sourceLocaleID: "en-US",
            targetLanguageID: store.mode.translationTarget(source: "en-US", target: "ja")))
        store.mode = .translation
        #expect(!(await availability.checkAndPrepare(sourceLocaleID: "en-US",
            targetLanguageID: store.mode.translationTarget(source: "en-US", target: "ja"))))
        store.phase = .listening
        store.appendFinal("Preserved until cleared")
        store.phase = .idle
        #expect(store.mode == .translation)
        store.reset()
        #expect(store.mode == .transcription)
        #expect(store.segments.isEmpty)
    }

    @Test func selectedTranslationSurvivesResumeAndResetsForNewMeeting() async throws {
        let fixture = DualFixture()
        let client = FakeMeetingTranslator()
        let suite = "TranscriptionModeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = MeetingWorkspace(controller: fixture.controller(), defaults: defaults, translationClient: client, prepareTranslationModels: false)
        meeting.mode = .translation
        meeting.microphoneTranslationLanguage = ""
        meeting.systemTranslationLanguage = "ja"
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("翻訳しない", time: 1)
        try await fixture.system.emit("Translate this", time: 1)
        await meeting.pause()
        #expect(meeting.mode == .translation)
        await meeting.start()
        fixture.system.finalOnStop = "Final sentence"
        await meeting.end()
        for _ in 0..<10_000 {
            if !meeting.translations.isWorking { break }
            await Task.yield()
        }
        #expect(await client.requests.count == 2)
        #expect(meeting.store.finals.count == 3)
        #expect(meeting.translations.completed.count == 2)
        meeting.mode = .transcription
        #expect(meeting.exportSnapshot?.translations?.count == 2)
        let old = try #require(meeting.store.finals.first { $0.origin == .systemAudio })
        #expect(meeting.translationTarget(for: old) == "ja")
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.mode == .transcription)
        #expect(meeting.systemTranslationLanguage == "ja")
        #expect(meeting.translations.entries.isEmpty)
    }

    @Test func onlyEligiblePartialsReserveTranslationSpaceAndOldFinalsDoNotGainPlaceholders() throws {
        let suite = "TranscriptionModeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), defaults: defaults)
        let partial = TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .systemAudio,
            languageCode: "en-US", startOffset: 1, endOffset: nil, text: "Hello", isFinal: false, revision: 1, sourceStartTime: 1)
        #expect(meeting.translationTarget(for: partial) == nil)
        meeting.mode = .translation
        meeting.systemTranslationLanguage = "ja"
        #expect(meeting.translationTarget(for: partial) == "ja")
        meeting.systemTranslationLanguage = "en"
        #expect(meeting.translationTarget(for: partial) == nil)
        meeting.systemTranslationLanguage = ""
        #expect(meeting.translationTarget(for: partial) == nil)
        meeting.mode = .transcription
        let final = TranscriptEvent(id: partial.id, sessionID: partial.sessionID, origin: partial.origin,
            languageCode: partial.languageCode, startOffset: 1, endOffset: 2, text: partial.text, isFinal: true, revision: 2, sourceStartTime: 1)
        meeting.store.receive(final)
        meeting.mode = .translation
        meeting.systemTranslationLanguage = "ja"
        #expect(meeting.translationTarget(for: final) == nil)
    }

    @Test func newMeetingDoesNotTranslateEvenWithRememberedTargets() async throws {
        let suite = "TranscriptionModeTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en", forKey: "meetingMicrophoneTranslation")
        defaults.set("ja", forKey: "meetingSystemTranslation")
        let fixture = DualFixture()
        let client = FakeMeetingTranslator()
        let meeting = MeetingWorkspace(controller: fixture.controller(), defaults: defaults,
                                       translationClient: client, prepareTranslationModels: false)
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("こんにちは", time: 1)
        fixture.system.finalOnStop = "Hello"
        await meeting.end()
        #expect(meeting.store.finals.count == 2)
        #expect(meeting.translations.lanes.isEmpty)
        #expect(meeting.translations.entries.isEmpty)
        #expect(await client.requests.isEmpty)
        #expect(meeting.exportSnapshot?.markdown.contains("Hello") == true)
    }
}
