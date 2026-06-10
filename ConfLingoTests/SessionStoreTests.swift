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
        #expect(store.segments[0].translationState == .pending)
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

    @Test func applyTranslationSetsJapaneseAndState() throws {
        let store = SessionStore()
        let id = try #require(store.appendFinal("Hello"))
        store.beginTranslating(id)
        #expect(store.segments[0].translationState == .translating)
        store.applyTranslation(id: id, japanese: "こんにちは")
        #expect(store.segments[0].japanese == "こんにちは")
        #expect(store.segments[0].translationState == .done)
    }

    @Test func markTranslationFailedSetsState() throws {
        let store = SessionStore()
        let id = try #require(store.appendFinal("Hello"))
        store.markTranslationFailed(id: id, reason: "network")
        #expect(store.segments[0].translationState == .failed("network"))
        #expect(store.segments[0].japanese == nil)
    }

    @Test func untranslatedSegmentsReturnsOnlyMissingJapanese() throws {
        let store = SessionStore()
        let a = try #require(store.appendFinal("A"))
        let b = try #require(store.appendFinal("B"))
        _ = b
        store.appendFinal("C")
        store.applyTranslation(id: a, japanese: "あ")
        #expect(store.untranslatedSegments.map(\.english) == ["B", "C"])
    }

    @Test func storesActiveKeywords() {
        let store = SessionStore()
        #expect(store.activeKeywords.isEmpty)
        store.setActiveKeywords(["Claude Code", "MCP"])
        #expect(store.activeKeywords == ["Claude Code", "MCP"])
        // 再 Start で上書きされる
        store.setActiveKeywords(["evals"])
        #expect(store.activeKeywords == ["evals"])
    }

    @Test func resetClearsSession() {
        let store = SessionStore()
        store.appendFinal("Hello")
        store.updateVolatile("partial")
        store.reset()
        #expect(store.segments.isEmpty)
        #expect(store.volatileText.isEmpty)
    }
}
