import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LiveTranscriptPerformanceTests {
    @Test func partialOnlyChangesReuseBothConferenceHistories() throws {
        let store = SessionStore()
        for index in 0..<300 {
            let segment = try #require(store.appendFinal("Final \(index)."))
            let unit = try #require(store.bufferSegment(segment))
            store.applyTranslation(id: unit.id, japanese: "確定 \(index)")
        }
        let pending = try #require(store.appendFinal("Pending"))
        _ = store.bufferSegment(pending)
        store.updateVolatile("First partial")
        let source = TranscriptPresentation.source(store)
        let translated = TranscriptPresentation.translation(store)
        for index in 0..<20 {
            store.updateVolatile("Partial \(index)")
            let nextSource = TranscriptPresentation.source(store)
            let nextTranslation = TranscriptPresentation.translation(store)
            #expect(nextSource.history === source.history)
            #expect(nextTranslation.history === translated.history)
            #expect(nextSource.last?.text == "Partial \(index)")
            #expect(nextTranslation.last?.reservationText == "Pending Partial \(index)")
            #expect(nextSource.update != source.update)
        }
        #expect(source.last?.text == "First partial")
        #expect(translated.last?.reservationText == "Pending First partial")
    }

    @Test func historyChangesInvalidateOnlyTheAffectedProjection() throws {
        let store = SessionStore()
        let id = try #require(store.appendFinal("Original."))
        let unit = try #require(store.bufferSegment(id))
        let source = TranscriptPresentation.source(store)
        let translated = TranscriptPresentation.translation(store)
        store.beginTranslating(unit.id)
        let working = TranscriptPresentation.translation(store)
        #expect(working.history !== translated.history)
        #expect(TranscriptPresentation.source(store).history === source.history)
        store.applyTranslation(id: unit.id, japanese: "原文")
        #expect(TranscriptPresentation.translation(store).first?.text == "原文")
        #expect(TranscriptPresentation.source(store).history === source.history)
        store.reset()
        #expect(TranscriptPresentation.source(store).isEmpty)
        #expect(TranscriptPresentation.translation(store).isEmpty)
        #expect(TranscriptPresentation.source(store).update != source.update)
    }

    @Test func correctionsPreparationAndBufferFlushInvalidateTheirVisibleRows() throws {
        let store = SessionStore()
        let first = try #require(store.appendFinal("First", startTime: 1))
        _ = store.bufferSegment(first)
        let second = try #require(store.appendFinal("part.", startTime: 2))
        let unit = try #require(store.bufferSegment(second))
        let original = TranscriptPresentation.source(store)
        var correction = ConferenceCorrection(id: UUID(), unitID: unit.id,
            original: TranscriptCorrectionInput(sourceText: unit.english, translation: nil, sourceLanguage: "en", targetLanguage: "ja", terms: []),
            sourceText: "Corrected sentence.", translation: "補正された文。", references: [reference()], adopted: true)
        let adopted = TranscriptPresentation.source(store, corrections: [correction])
        #expect(adopted.map(\.id) == [first.uuidString])
        #expect(adopted.first?.text == "Corrected sentence. （補正採用）")
        #expect(adopted.first?.time == 1)
        #expect(TranscriptPresentation.translation(store, corrections: [correction]).first?.text == "補正された文。 （補正採用）")
        store.updateVolatile("Next")
        #expect(TranscriptPresentation.source(store, corrections: [correction]).history === adopted.history)
        correction.adopted = false
        #expect(TranscriptPresentation.source(store, corrections: [correction]).history.entries == original.history.entries)
        let preparing = TranscriptPresentation.translation(store, preparation: .preparing)
        #expect(preparing.first?.text.contains("準備しています") == true)
        let failed = TranscriptPresentation.translation(store, preparation: .failed("unavailable"))
        #expect(failed.first?.status == .failed)
        let ready = TranscriptPresentation.translation(store, preparation: .ready)
        #expect(ready.first?.status == .translating)
        let pending = try #require(store.appendFinal("Unfinished"))
        _ = store.bufferSegment(pending)
        store.updateVolatile("Still speaking")
        let beforeFlush = TranscriptPresentation.translation(store)
        #expect(beforeFlush.last?.reservationText == "Unfinished Still speaking")
        _ = try #require(store.flushBuffer())
        let afterFlush = TranscriptPresentation.translation(store)
        #expect(afterFlush.last?.id != beforeFlush.last?.id)
        #expect(afterFlush.last?.reservationText == "Still speaking")
        store.markTranslationFailed(id: unit.id, reason: "failed")
        #expect(TranscriptPresentation.translation(store).first?.status == .failed)
    }

    @Test func resetReleasesCachedHistoryWithoutAnotherRead() throws {
        let store = SessionStore()
        _ = try #require(store.appendFinal("Retained until reset."))
        weak var history = TranscriptPresentation.source(store).history
        #expect(history != nil)
        store.reset()
        #expect(history == nil)
    }

    @Test func meetingDisplayNotificationsIgnoreRejectedUpdatesAndCoverClearAndReset() {
        let store = MeetingSessionStore(sessionID: UUID())
        func event(_ id: UUID, final: Bool, revision: Int) -> TranscriptEvent {
            TranscriptEvent(id: id, sessionID: store.sessionID, origin: .microphone, languageCode: "en", startOffset: 1,
                endOffset: 2, text: "Revision \(revision)", isFinal: final, revision: revision, sourceStartTime: 1)
        }
        let id = UUID()
        let initial = store.displayRevision
        let partial = event(id, final: false, revision: 1)
        #expect(store.receive(partial))
        let accepted = store.displayRevision
        #expect(accepted != initial)
        #expect(!store.receive(partial))
        #expect(!store.receive(insightEvent()))
        #expect(!store.receive(insightEvent(session: store.sessionID, text: " ")))
        #expect(store.displayRevision == accepted)
        #expect(store.receive(event(id, final: true, revision: 2)))
        let finalized = store.displayRevision
        #expect(finalized != accepted)
        #expect(!store.receive(event(id, final: true, revision: 3)))
        store.clearPartials()
        #expect(store.displayRevision == finalized)
        #expect(store.receive(event(UUID(), final: false, revision: 1)))
        let beforeClear = store.displayRevision
        store.clearPartials()
        #expect(store.displayRevision != beforeClear)
        let beforeReset = store.displayRevision
        store.reset(sessionID: UUID())
        #expect(store.displayRevision != beforeReset)
        #expect(store.finals.isEmpty && store.partials.isEmpty)
    }

    @Test func translationNotificationsCoverFailureRetryCompletionAndReset() async throws {
        let client = FakeMeetingTranslator()
        let translations = MeetingTranslations(sessionID: UUID(), client: client)
        let event = insightEvent(session: translations.sessionID)
        let initial = translations.displayRevision
        translations.receive(event, targetLanguage: "ja")
        let queued = translations.displayRevision
        #expect(queued != initial)
        translations.receive(event, targetLanguage: "ja")
        #expect(translations.displayRevision == queued)
        let lane = try #require(translations.lanes.first)
        translations.preparationFailed(lane.id, generation: lane.generation, message: "unavailable")
        let failed = translations.displayRevision
        #expect(failed != queued)
        translations.retry(event.id)
        #expect(translations.displayRevision != failed)
        let retrying = translations.displayRevision
        translations.prepared(lane.id, generation: lane.generation)
        for _ in 0..<10_000 {
            if !translations.isWorking { break }
            await Task.yield()
        }
        #expect(translations.completed.count == 1)
        #expect(translations.displayRevision != retrying)
        let completed = translations.displayRevision
        translations.reset(sessionID: UUID())
        #expect(translations.displayRevision != completed)
        #expect(translations.completed.isEmpty)
    }
}
