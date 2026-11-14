import Foundation
import Synchronization
import Testing
import Translation
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppleMeetingTranslatorReuseTests {
    @Test func reusesBackendAcrossRequestsAndAfterAnIndividualFailure() async throws {
        let creations = Mutex(0)
        let translations = MeetingTranslations(sessionID: UUID(), clientFactory: { _, _ in
            AppleMeetingTranslator { source, target in
                let number = creations.withLock { count in count += 1; return count }
                return CountingTranslationBackend(number: number, source: source, target: target)
            }
        }, requiresPreparation: false)
        #expect(creations.withLock { $0 } == 0)
        let first = translationEvent(translations.sessionID)
        translations.receive(first, targetLanguage: "ja")
        await settleTranslations(translations)
        #expect(translations.entries[first.id]?.translation?.text == "1:en:ja:Hello")
        let failed = translationEvent(translations.sessionID, text: "fail")
        translations.receive(failed, targetLanguage: "ja")
        let last = translationEvent(translations.sessionID)
        translations.receive(last, targetLanguage: "ja")
        await settleTranslations(translations)
        #expect(translations.entries[failed.id]?.translation == nil)
        #expect(translations.entries[last.id]?.translation?.text == "1:en:ja:Hello")
        #expect(creations.withLock { $0 } == 1)
        translations.reset(sessionID: UUID())
    }

    @Test func appleAdapterUsesMaskedInputAndTheSameBackendForFallback() async {
        let creations = Mutex(0)
        let inputs = TranslationInputLog()
        let translations = MeetingTranslations(sessionID: UUID(), clientFactory: { _, _ in
            AppleMeetingTranslator { _, _ in
                creations.withLock { $0 += 1 }
                return FallbackTranslationBackend(inputs: inputs)
            }
        }, requiresPreparation: false)
        translations.termsForRequest = { _ in ["Photon"] }
        let event = translationEvent(translations.sessionID, text: "Photon")
        translations.receive(event, targetLanguage: "ja")
        await settleTranslations(translations)
        #expect(inputs.values.withLock { $0 } == ["⟦0⟧", "Photon"])
        #expect(creations.withLock { $0 } == 1)
        #expect(translations.entries[event.id]?.translation?.text == "fallback Photon")
        translations.reset(sessionID: UUID())
    }

}

private final class CountingTranslationBackend: MeetingTranslationBackend {
    let number: Int
    let source: String
    let target: String
    init(number: Int, source: String, target: String) {
        self.number = number
        self.source = source
        self.target = target
    }
    func translate(_ text: String) async throws -> TranslationSession.Response {
        if text == "fail" { throw CocoaError(.fileReadUnknown) }
        return TranslationSession.Response(sourceLanguage: Locale.Language(identifier: source),
            targetLanguage: Locale.Language(identifier: target), sourceText: text,
            targetText: "\(number):\(source):\(target):\(text)")
    }
}

func translationEvent(_ session: UUID, origin: AudioOrigin = .systemAudio, text: String = "Hello",
                      language: String = "en-US") -> TranscriptEvent {
    TranscriptEvent(id: UUID(), sessionID: session, origin: origin, languageCode: language,
                    startOffset: 1, endOffset: 2, text: text, isFinal: true, revision: 1, sourceStartTime: 1)
}

@MainActor
func settleTranslations(_ translations: MeetingTranslations) async {
    for _ in 0..<10_000 {
        if !translations.isWorking { return }
        await Task.yield()
    }
    Issue.record("Translation queue did not finish")
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingTranslationLaneReuseTests {
    @Test func sharesNormalizedPairAcrossInputsButSeparatesDirectionsAndTargets() async {
        var clients: [FakeMeetingTranslator] = []
        var pairs: [String] = []
        let translations = MeetingTranslations(sessionID: UUID(), clientFactory: { source, target in
            let client = FakeMeetingTranslator()
            clients.append(client)
            pairs.append("\(source)>\(target)")
            return client
        }, requiresPreparation: false)
        let session = translations.sessionID
        translations.receive(translationEvent(session), targetLanguage: "ja")
        translations.receive(translationEvent(session, origin: .microphone, language: "en"), targetLanguage: "ja-JP")
        await settleTranslations(translations)
        translations.receive(translationEvent(session), targetLanguage: "ja")
        translations.receive(translationEvent(session, language: "ja-JP"), targetLanguage: "en")
        translations.receive(translationEvent(session), targetLanguage: "fr")
        await settleTranslations(translations)
        #expect(pairs == ["en>ja", "ja>en", "en>fr"])
        #expect(await clients[0].requests.count == 3)
        #expect(await clients[1].requests.count == 1)
        #expect(await clients[2].requests.count == 1)
        #expect(translations.completed.count == 5)
        translations.reset(sessionID: UUID())
    }

    @Test func failedPreparationAndObsoleteCallbacksCannotCreateAWorker() async throws {
        var creations = 0
        let translations = MeetingTranslations(sessionID: UUID(), clientFactory: { _, _ in
            creations += 1
            return FakeMeetingTranslator()
        })
        let event = translationEvent(translations.sessionID)
        translations.receive(event, targetLanguage: "ja")
        let lane = try #require(translations.lanes.first)
        let old = lane.generation
        translations.preparationFailed(lane.id, generation: old, message: "offline")
        #expect(creations == 0)
        translations.retry(event.id)
        translations.prepared(lane.id, generation: old)
        translations.preparationFailed(lane.id, generation: old, message: "late")
        #expect(creations == 0)
        translations.prepared(lane.id, generation: lane.generation)
        await settleTranslations(translations)
        translations.prepared(lane.id, generation: lane.generation)
        translations.preparationFailed(lane.id, generation: lane.generation, message: "late after success")
        #expect(creations == 1)
        #expect(lane.ready)
        #expect(lane.error == nil)
        #expect(translations.completed.count == 1)
        translations.reset(sessionID: UUID())
    }

    @Test func resetRejectsLateResultsAndReleasesOldLaneAndClient() async throws {
        let gate = TestGate()
        weak var oldClient: FakeMeetingTranslator?
        weak var oldLane: MeetingTranslationLane?
        var creations = 0
        let translations = MeetingTranslations(sessionID: UUID(), clientFactory: { _, _ in
            creations += 1
            let client = FakeMeetingTranslator(gate: creations == 1 ? gate : nil)
            if creations == 1 { oldClient = client }
            return client
        }, requiresPreparation: false)
        let oldEvent = translationEvent(translations.sessionID)
        translations.receive(oldEvent, targetLanguage: "ja")
        oldLane = translations.lanes.first
        let task = try #require(oldLane?.task)
        await gate.entered.next()
        translations.reset(sessionID: UUID())
        let current = translationEvent(translations.sessionID, text: "new meeting")
        translations.receive(current, targetLanguage: "ja")
        await settleTranslations(translations)
        gate.release()
        await task.value
        #expect(creations == 2)
        #expect(translations.entries[oldEvent.id] == nil)
        #expect(translations.completed.map(\.text) == ["ja:new meeting"])
        #expect(oldLane == nil)
        #expect(oldClient == nil)
        translations.reset(sessionID: UUID())
    }

    @Test func pauseAndResumeKeepTheWorkerAndDrainFinalSpeechOnEnd() async throws {
        let fixture = DualFixture()
        var creations = 0
        let meeting = MeetingWorkspace(controller: fixture.controller(), translationClientFactory: { _, _ in
            creations += 1
            return FakeMeetingTranslator()
        }, prepareTranslationModels: false)
        meeting.mode = .translation
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.system.emit("before pause", time: 1)
        await meeting.pause()
        await settleTranslations(meeting.translations)
        await meeting.start()
        fixture.system.finalOnStop = "last sentence"
        await meeting.end()
        await settleTranslations(meeting.translations)
        #expect(creations == 1)
        #expect(meeting.translations.completed.count == 2)
        #expect(meeting.exportSnapshot?.markdown.contains("ja:last sentence") == true)
        meeting.translations.reset(sessionID: UUID())
    }
}

private final class FallbackTranslationBackend: MeetingTranslationBackend {
    let inputs: TranslationInputLog
    init(inputs: TranslationInputLog) { self.inputs = inputs }
    func translate(_ text: String) async throws -> TranslationSession.Response {
        let count = inputs.values.withLock { values in values.append(text); return values.count }
        return TranslationSession.Response(sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: "ja"), sourceText: text,
            targetText: count == 1 ? "lost token" : "fallback " + text)
    }
}

private final class TranslationInputLog: Sendable {
    let values = Mutex<[String]>([])
}
