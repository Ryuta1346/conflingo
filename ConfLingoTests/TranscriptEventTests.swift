import Foundation
import Testing
@testable import ConfLingo

func transcriptEvent(
    id: UUID = UUID(), sessionID: UUID, origin: AudioOrigin = .microphone,
    text: String = "Hello", isFinal: Bool = true, revision: Int = 1
) -> TranscriptEvent {
    TranscriptEvent(
        id: id, sessionID: sessionID, origin: origin, languageCode: "en-US",
        startOffset: 12, endOffset: 13, text: text, isFinal: isFinal,
        revision: revision, sourceStartTime: 2
    )
}

@MainActor
struct TranscriptEventTests {
    @Test func partialRevisionsBecomeOneFinalAndCannotRegress() {
        let store = MeetingSessionStore(sessionID: UUID())
        let id = UUID()
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, text: "Hel", isFinal: false))
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, text: "Hello", isFinal: false, revision: 2))
        #expect(store.partials.map(\.text) == ["Hello"])
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, revision: 3))
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, text: "Old", isFinal: false, revision: 2))
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, text: "Late", isFinal: false, revision: 4))
        store.receive(transcriptEvent(id: id, sessionID: store.sessionID, revision: 3))
        #expect(store.partials.isEmpty)
        #expect(store.finals.map(\.text) == ["Hello"])
    }

    @Test func distinctUtterancesAndOriginsSurviveIdenticalText() {
        let store = MeetingSessionStore(sessionID: UUID())
        let first = transcriptEvent(sessionID: store.sessionID)
        store.receive(first)
        store.receive(first)
        store.receive(transcriptEvent(sessionID: store.sessionID))
        store.receive(transcriptEvent(sessionID: store.sessionID, origin: .systemAudio))
        #expect(store.finals.map(\.origin) == [.microphone, .microphone, .systemAudio])
        #expect(store.finals.map(\.languageCode) == ["en-US", "en-US", "en-US"])
        #expect(store.finals.map(\.text) == ["Hello", "Hello", "Hello"])
        #expect(Set(store.finals.map(\.id)).count == 3)
    }

    @Test func resetRejectsOldSessionAndEmptyText() {
        let store = MeetingSessionStore(sessionID: UUID())
        let old = transcriptEvent(sessionID: store.sessionID)
        store.receive(old)
        store.reset(sessionID: UUID())
        store.receive(old)
        store.receive(transcriptEvent(sessionID: store.sessionID, text: " \n"))
        #expect(store.finals.isEmpty)
        #expect(store.partials.isEmpty)
    }

    @Test func normalizerKeepsIDAcrossGrowingRangeAndStartsNewAfterFinal() throws {
        var normalizer = TranscriptEventNormalizer(
            sessionID: UUID(), origin: .microphone, languageCode: "ja-JP", inputOffset: 10
        )
        let firstResult = normalizer.makeEvent(
            SpeechResult(text: "こん", isFinal: false, startTime: 2, endTime: 3), receivedOffset: 14
        )
        let first = try #require(firstResult)
        let finalResult = normalizer.makeEvent(
            SpeechResult(text: "こんにちは", isFinal: true, startTime: 2, endTime: 4), receivedOffset: 15
        )
        let final = try #require(finalResult)
        let nextResult = normalizer.makeEvent(
            SpeechResult(text: "次", isFinal: true, startTime: 5, endTime: 6), receivedOffset: 17
        )
        let next = try #require(nextResult)
        #expect(first.id == final.id)
        #expect(final.revision == 2)
        #expect(final.startOffset == 12)
        #expect(final.endOffset == 14)
        #expect(final.sourceStartTime == 2)
        #expect(final.languageCode == "ja-JP")
        #expect(next.id != final.id)
    }

    @Test func invalidTimesUseReceiveOffsetAndDoNotLeakNaN() throws {
        var normalizer = TranscriptEventNormalizer(
            sessionID: UUID(), origin: .systemAudio, languageCode: "en-US", inputOffset: 10
        )
        let eventResult = normalizer.makeEvent(
            SpeechResult(text: "Hello", isFinal: true, startTime: .nan, endTime: .infinity), receivedOffset: 18
        )
        let event = try #require(eventResult)
        #expect(event.startOffset == 18)
        #expect(event.endOffset == nil)
        #expect(event.sourceStartTime == nil)
        let empty = normalizer.makeEvent(
            SpeechResult(text: "  ", isFinal: true, startTime: 0, endTime: 1), receivedOffset: 18
        )
        #expect(empty == nil)
    }

    @Test func timelineIncludesPauseUntilExplicitReset() {
        var now = 100.0
        let timeline = MeetingTimeline(now: { now })
        let session = timeline.sessionID
        #expect(timeline.beginInput() == 0)
        now = 125
        #expect(timeline.beginInput() == 25)
        #expect(timeline.sessionID == session)
        timeline.reset()
        #expect(timeline.sessionID != session)
        now = 200
        #expect(timeline.beginInput() == 0)
    }
}
