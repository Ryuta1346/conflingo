import Testing
@testable import ConfLingo

@MainActor
struct TranscriptPresentationTests {
    @Test func partialAndFinalKeepDistinctIdentityAndTimestamp() {
        let store = SessionStore()
        let id = store.appendFinal("Final words.", startTime: 12)!
        store.updateVolatile("Still speaking")
        let entries = TranscriptPresentation.source(store)
        #expect(entries.count == 2)
        #expect(entries[0].id == id.uuidString)
        #expect(entries[0].time == 12)
        #expect(entries[0].status == .final)
        #expect(entries[1].status == .recognizing)
        #expect(entries[1].time == nil)
    }

    @Test func translationUsesCombinedUnitsInsteadOfAligningWithSegments() {
        let store = SessionStore()
        let first = store.appendFinal("A long", startTime: 10)!
        #expect(store.bufferSegment(first) == nil)
        let second = store.appendFinal("sentence.", startTime: 11)!
        let unit = store.bufferSegment(second)!
        store.applyTranslation(id: unit.id, japanese: "長い文です。")
        let entries = TranscriptPresentation.translation(store)
        #expect(entries.count == 1)
        #expect(entries[0].text == "長い文です。")
        #expect(entries[0].time == 10)
        #expect(store.segments.count == 2)
    }

    @Test func translationFailureAndBufferedTextStayVisible() {
        let store = SessionStore()
        let id = store.appendFinal("First sentence.")!
        let unit = store.bufferSegment(id)!
        store.markTranslationFailed(id: unit.id, reason: "network")
        let pending = store.appendFinal("Unfinished")!
        _ = store.bufferSegment(pending)
        let entries = TranscriptPresentation.translation(store)
        #expect(entries.map(\.status) == [.failed, .translating])
        #expect(entries[0].text.contains("翻訳できませんでした"))
        #expect(TranscriptPresentation.source(store).count == 2)
    }
}
