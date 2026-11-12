import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingTranslationTests {
    @Test func translatesBothInputsWithoutChangingOriginalsOrTranslatingPartials() async throws {
        let client = FakeMeetingTranslator()
        let session = UUID()
        let translations = MeetingTranslations(sessionID: session, client: client)
        let microphone = event(session, origin: .microphone, text: "こんにちは", language: "ja-JP")
        let system = event(session, origin: .systemAudio, text: "Hello", language: "en-US")
        translations.receive(event(session, text: "Hel", final: false), targetLanguage: "ja")
        translations.receive(microphone, targetLanguage: "en")
        translations.receive(system, targetLanguage: "ja")
        translations.receive(system, targetLanguage: "ja")
        #expect(await client.requests.isEmpty)
        prepare(translations)
        await settle(translations)
        #expect(await client.requests.count == 2)
        #expect(translations.completed.count == 2)
        #expect(translations.entries[microphone.id]?.translation?.text == "en:こんにちは")
        #expect(translations.entries[system.id]?.translation?.text == "ja:Hello")
        #expect(system.text == "Hello")
    }

    @Test func skipsDisabledSameLanguageAndForeignSession() {
        let session = UUID()
        let translations = MeetingTranslations(sessionID: session, client: FakeMeetingTranslator())
        translations.receive(event(session), targetLanguage: nil)
        translations.receive(event(session), targetLanguage: "en")
        translations.receive(event(UUID()), targetLanguage: "ja")
        #expect(translations.entries.isEmpty)
        #expect(translations.lanes.isEmpty)
    }

    @Test func failureOnOnePairDoesNotBlockOtherPairAndRetryPreservesCompletedResults() async throws {
        let session = UUID()
        let translations = MeetingTranslations(sessionID: session, client: FakeMeetingTranslator())
        let first = event(session)
        let other = event(session, origin: .microphone, text: "こんにちは", language: "ja-JP")
        translations.receive(first, targetLanguage: "ja")
        translations.receive(other, targetLanguage: "en")
        let lane = try #require(translations.lanes.first { $0.targetLanguage == "ja" })
        translations.preparationFailed(lane.id, generation: lane.generation, message: "Download cancelled")
        let secondLane = try #require(translations.lanes.first { $0.targetLanguage == "en" })
        translations.prepared(secondLane.id, generation: secondLane.generation)
        await settle(translations)
        #expect(translations.entries[first.id]?.state == .failed("Download cancelled"))
        let completed = translations.entries[other.id]?.translation
        let generation = lane.generation
        translations.retry(first.id)
        #expect(lane.generation != generation)
        translations.prepared(lane.id, generation: generation)
        #expect(!lane.ready)
        translations.prepared(lane.id, generation: lane.generation)
        await settle(translations)
        #expect(translations.completed.count == 2)
        #expect(translations.entries[other.id]?.translation == completed)
    }

    @Test func translationFailureCanRetryWithoutLosingOtherQueuedUtterances() async throws {
        let session = UUID()
        let client = FakeMeetingTranslator()
        await client.failNext()
        let translations = MeetingTranslations(sessionID: session, client: client)
        let first = event(session, text: "first")
        let second = event(session, text: "second")
        translations.receive(first, targetLanguage: "ja")
        translations.receive(second, targetLanguage: "ja")
        prepare(translations)
        await settle(translations)
        #expect(translations.entries[first.id]?.translation == nil)
        #expect(translations.entries[second.id]?.translation?.text == "ja:second")
        translations.retry(first.id)
        prepare(translations)
        await settle(translations)
        #expect(translations.completed.count == 2)
        #expect(await client.requests.count == 3)
    }

    @Test func resettingRejectsLateTranslationAndLanguageChangesPreserveExistingTargets() async throws {
        let session = UUID()
        let gate = TestGate()
        let client = FakeMeetingTranslator(gate: gate)
        let translations = MeetingTranslations(sessionID: session, client: client)
        translations.receive(event(session), targetLanguage: "ja")
        prepare(translations)
        await gate.entered.next()
        translations.reset(sessionID: UUID())
        gate.release()
        for _ in 0..<50 { await Task.yield() }
        #expect(translations.entries.isEmpty)
        #expect(translations.lanes.isEmpty)

        let current = translations.sessionID
        let first = event(current)
        let second = event(current)
        translations.receive(first, targetLanguage: "ja")
        translations.receive(second, targetLanguage: "fr")
        #expect(translations.entries[first.id]?.request.targetLanguage == "ja")
        #expect(translations.entries[second.id]?.request.targetLanguage == "fr")
    }

    @Test func meetingDrainsStopFinalsAndResumeKeepsCompletedTranslations() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), translationClient: FakeMeetingTranslator())
        meeting.mode = .translation
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.system.emit("before pause", time: 1)
        await meeting.pause()
        prepare(meeting.translations)
        await settle(meeting.translations)
        let first = meeting.translations.completed
        await meeting.start()
        fixture.system.finalOnStop = "last sentence"
        await meeting.end()
        prepare(meeting.translations)
        await settle(meeting.translations)
        #expect(meeting.translations.completed.count == 2)
        #expect(meeting.translations.completed.contains(first[0]))
        #expect(meeting.exportSnapshot?.translations?.count == 2)
        #expect(meeting.exportSnapshot?.markdown.contains("ja:last sentence") == true)
    }

    private func event(_ session: UUID, origin: AudioOrigin = .systemAudio, text: String = "Hello",
                       language: String = "en-US", final: Bool = true) -> TranscriptEvent {
        TranscriptEvent(id: UUID(), sessionID: session, origin: origin, languageCode: language,
                        startOffset: 1, endOffset: 2, text: text, isFinal: final, revision: 1, sourceStartTime: 1)
    }

    private func prepare(_ translations: MeetingTranslations) {
        for lane in translations.lanes { translations.prepared(lane.id, generation: lane.generation) }
    }

    private func settle(_ translations: MeetingTranslations) async {
        for _ in 0..<10_000 {
            if !translations.isWorking { return }
            await Task.yield()
        }
        Issue.record("Translation queue did not finish")
    }
}

actor FakeMeetingTranslator: MeetingTranslating {
    private(set) var requests: [MeetingTranslationRequest] = []
    private var shouldFail = false
    private let gate: TestGate?

    init(gate: TestGate? = nil) { self.gate = gate }
    func failNext() { shouldFail = true }

    func translate(_ request: MeetingTranslationRequest) async throws -> String {
        requests.append(request)
        if let gate { await gate.wait() }
        if shouldFail { shouldFail = false; throw CocoaError(.fileReadUnknown) }
        return "\(request.targetLanguage):\(request.event.text)"
    }
}
