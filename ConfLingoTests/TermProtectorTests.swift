import Foundation
import Testing
@testable import ConfLingo

struct TermProtectorTests {
    @Test func masksSingleTerm() {
        let (masked, mapping) = TermProtector.mask("I love Claude Code today", terms: ["Claude Code"])
        #expect(masked == "I love ⟦0⟧ today")
        #expect(mapping == ["⟦0⟧": "Claude Code"])
    }

    @Test func roundtripRestoresOriginal() {
        let text = "Claude Code and MCP are great"
        let (masked, mapping) = TermProtector.mask(text, terms: ["Claude Code", "MCP"])
        // 翻訳されなかった場合（恒等変換）に元へ戻ること
        #expect(TermProtector.unmask(masked, mapping: mapping) == text)
    }

    @Test func longestMatchWins() {
        let (masked, mapping) = TermProtector.mask("Claude Code is here", terms: ["Claude", "Claude Code"])
        #expect(masked == "⟦0⟧ is here")
        #expect(mapping == ["⟦0⟧": "Claude Code"])
    }

    @Test func respectsWordBoundary() {
        let (masked, mapping) = TermProtector.mask("He is skillful", terms: ["skill"])
        #expect(masked == "He is skillful")
        #expect(mapping.isEmpty)
    }

    @Test func matchesAdjacentToJapanese() {
        // 日本語が隣接していても英単語はマッチする（ja ソース対応）
        let (masked, mapping) = TermProtector.mask("Claudeです", terms: ["Claude"])
        #expect(masked == "⟦0⟧です")
        #expect(mapping == ["⟦0⟧": "Claude"])
    }

    @Test func caseInsensitiveMatchPreservesSourceForm() {
        let (masked, mapping) = TermProtector.mask("the mcp server", terms: ["MCP"])
        #expect(masked == "the ⟦0⟧ server")
        // 復元されるのはソース上の実際の表記
        #expect(mapping == ["⟦0⟧": "mcp"])
    }

    @Test func numbersMultipleOccurrencesInOrder() {
        let (masked, mapping) = TermProtector.mask("Claude calls Claude", terms: ["Claude"])
        #expect(masked == "⟦0⟧ calls ⟦1⟧")
        #expect(mapping == ["⟦0⟧": "Claude", "⟦1⟧": "Claude"])
    }

    @Test func noTermsIsPassthrough() {
        let (masked, mapping) = TermProtector.mask("hello world", terms: [])
        #expect(masked == "hello world")
        #expect(mapping.isEmpty)
    }

    @Test func emptyTextIsPassthrough() {
        let (masked, mapping) = TermProtector.mask("", terms: ["Claude"])
        #expect(masked.isEmpty)
        #expect(mapping.isEmpty)
    }

    @Test func unmaskIgnoresMissingTokens() {
        // 翻訳エンジンがプレースホルダを崩した場合は翻訳文をそのまま返す（クラッシュ・エラーにしない）
        let result = TermProtector.unmask("こんにちは", mapping: ["⟦0⟧": "Claude"])
        #expect(result == "こんにちは")
    }

    @Test func unmaskRestoresIntoTranslatedText() {
        let result = TermProtector.unmask("⟦0⟧は素晴らしい", mapping: ["⟦0⟧": "Claude Code"])
        #expect(result == "Claude Codeは素晴らしい")
    }
}
