import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SessionStoreTests {
    @Test func appendFinalAddsSegment() {
        let store = SessionStore()
        let id = store.appendFinal("Hello world")
        #expect(id != nil)
        #expect(store.segments.count == 1)
        #expect(store.segments[0].english == "Hello world")
        #expect(store.segments[0].index == 1)
    }

    @Test func appendFinalStoresStartTime() {
        let store = SessionStore()
        store.appendFinal("Hello", startTime: 225.0)
        #expect(store.segments[0].startTime == 225.0)
        // 省略時は nil（時刻不明）
        store.appendFinal("World")
        #expect(store.segments[1].startTime == nil)
    }

    @Test func appendFinalTrimsWhitespace() {
        let store = SessionStore()
        store.appendFinal("  Hello  \n")
        #expect(store.segments[0].english == "Hello")
    }

    @Test func appendFinalRejectsEmptyText() {
        let store = SessionStore()
        #expect(store.appendFinal("") == nil)
        #expect(store.appendFinal("   \n ") == nil)
        #expect(store.segments.isEmpty)
    }

    @Test func appendFinalRejectsConsecutiveDuplicate() {
        let store = SessionStore()
        let first = store.appendFinal("Same sentence")
        let second = store.appendFinal("Same sentence")
        #expect(first != nil)
        #expect(second == nil)
        #expect(store.segments.count == 1)
    }

    @Test func appendFinalAllowsNonConsecutiveDuplicate() {
        let store = SessionStore()
        store.appendFinal("A")
        store.appendFinal("B")
        let third = store.appendFinal("A")
        #expect(third != nil)
        #expect(store.segments.count == 3)
    }

    @Test func appendFinalClearsVolatileText() {
        let store = SessionStore()
        store.updateVolatile("partial text")
        #expect(store.volatileText == "partial text")
        store.appendFinal("Final text")
        #expect(store.volatileText.isEmpty)
    }

    @Test func segmentIndexIncrements() {
        let store = SessionStore()
        store.appendFinal("One")
        store.appendFinal("Two")
        #expect(store.segments.map(\.index) == [1, 2])
    }

    // MARK: - 翻訳単位（TranslationUnit）バッファリング

    /// 文末まで final を投入して unit を1つ確定させるヘルパー
    private func makeUnit(_ store: SessionStore, _ text: String) throws -> TranslationUnit {
        let id = try #require(store.appendFinal(text))
        return try #require(store.bufferSegment(id))
    }

    @Test func bufferSegmentHoldsFragmentUntilSentenceEnd() throws {
        let store = SessionStore()
        let a = try #require(store.appendFinal("This is the first half"))
        #expect(store.bufferSegment(a) == nil)
        #expect(store.bufferedSegmentIDs == [a])

        let b = try #require(store.appendFinal("and this finishes it."))
        let unit = try #require(store.bufferSegment(b))
        #expect(unit.english == "This is the first half and this finishes it.")
        #expect(unit.segmentIDs == [a, b])
        #expect(unit.index == 1)
        #expect(store.units.count == 1)
        #expect(store.bufferedSegmentIDs.isEmpty)
    }

    @Test func bufferSegmentFlushesImmediatelyOnSentenceEnd() throws {
        let store = SessionStore()
        let unit = try makeUnit(store, "Hello everyone.")
        #expect(unit.english == "Hello everyone.")
        #expect(unit.segmentIDs.count == 1)
    }

    @Test func bufferSegmentFlushesOnSegmentCountLimit() throws {
        let store = SessionStore()
        var unit: TranslationUnit?
        for i in 1...4 {
            let id = try #require(store.appendFinal("fragment \(i) without punctuation"))
            unit = store.bufferSegment(id)
            if i < 4 {
                #expect(unit == nil)
            }
        }
        // 4セグメント目で文末がなくても強制 flush（暴走ガード）
        #expect(unit != nil)
        #expect(unit?.segmentIDs.count == 4)
    }

    @Test func bufferSegmentFlushesOnCharacterLimit() throws {
        let store = SessionStore()
        let long = String(repeating: "word ", count: 90).trimmingCharacters(in: .whitespaces)
        let id = try #require(store.appendFinal(long))
        // 400文字以上なら文末がなくても flush
        let unit = try #require(store.bufferSegment(id))
        #expect(unit.english == long)
    }

    @Test func flushBufferForcesPendingFragment() throws {
        let store = SessionStore()
        let a = try #require(store.appendFinal("unfinished fragment"))
        #expect(store.bufferSegment(a) == nil)
        let unit = try #require(store.flushBuffer())
        #expect(unit.english == "unfinished fragment")
        #expect(store.bufferedSegmentIDs.isEmpty)
        // バッファが空なら nil
        #expect(store.flushBuffer() == nil)
    }

    @Test func unitStartTimeComesFromFirstSegment() throws {
        let store = SessionStore()
        let a = try #require(store.appendFinal("first part", startTime: 10.0))
        #expect(store.bufferSegment(a) == nil)
        let b = try #require(store.appendFinal("second part.", startTime: 15.0))
        let unit = try #require(store.bufferSegment(b))
        #expect(unit.startTime == 10.0)
    }

    @Test func unitIndexIncrements() throws {
        let store = SessionStore()
        let first = try makeUnit(store, "One.")
        let second = try makeUnit(store, "Two.")
        #expect(first.index == 1)
        #expect(second.index == 2)
    }

    @Test func applyTranslationSetsJapaneseAndState() throws {
        let store = SessionStore()
        let unit = try makeUnit(store, "Hello.")
        #expect(store.units[0].translationState == .pending)
        store.beginTranslating(unit.id)
        #expect(store.units[0].translationState == .translating)
        store.applyTranslation(id: unit.id, japanese: "こんにちは。")
        #expect(store.units[0].japanese == "こんにちは。")
        #expect(store.units[0].translationState == .done)
    }

    @Test func markTranslationFailedSetsState() throws {
        let store = SessionStore()
        let unit = try makeUnit(store, "Hello.")
        store.markTranslationFailed(id: unit.id, reason: "network")
        #expect(store.units[0].translationState == .failed("network"))
        #expect(store.units[0].japanese == nil)
    }

    @Test func untranslatedUnitsReturnsOnlyMissingJapanese() throws {
        let store = SessionStore()
        let a = try makeUnit(store, "A.")
        _ = try makeUnit(store, "B.")
        _ = try makeUnit(store, "C.")
        store.applyTranslation(id: a.id, japanese: "あ。")
        #expect(store.untranslatedUnits.map(\.english) == ["B.", "C."])
    }

    @Test func storesActiveGlossary() {
        let store = SessionStore()
        #expect(store.activeGlossary.isEmpty)
        let first = [
            KeywordParser.GlossaryEntry(term: "Claude Code", target: nil),
            KeywordParser.GlossaryEntry(term: "evals", target: "評価"),
        ]
        store.setActiveGlossary(first)
        #expect(store.activeGlossary == first)
        // 再 Start で上書きされる
        let second = [KeywordParser.GlossaryEntry(term: "MCP", target: nil)]
        store.setActiveGlossary(second)
        #expect(store.activeGlossary == second)
    }

    @Test func resetClearsSession() throws {
        let store = SessionStore()
        _ = try makeUnit(store, "Hello.")
        let pending = try #require(store.appendFinal("unfinished"))
        _ = store.bufferSegment(pending)
        store.updateVolatile("partial")
        store.reset()
        #expect(store.segments.isEmpty)
        #expect(store.units.isEmpty)
        #expect(store.bufferedSegmentIDs.isEmpty)
        #expect(store.volatileText.isEmpty)
    }
}
