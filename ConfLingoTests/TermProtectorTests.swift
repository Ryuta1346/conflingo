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
        let result = TermProtector.unmask(masked, mapping: mapping)
        #expect(result.text == text)
        #expect(result.unresolvedTokens.isEmpty)
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

    @Test func unmaskReportsMissingTokens() {
        // 翻訳エンジンがプレースホルダを消した場合は翻訳文をそのまま返し、未解決として報告する
        let result = TermProtector.unmask("こんにちは", mapping: ["⟦0⟧": "Claude"])
        #expect(result.text == "こんにちは")
        #expect(result.unresolvedTokens == ["⟦0⟧"])
    }

    @Test func unmaskRestoresIntoTranslatedText() {
        let result = TermProtector.unmask("⟦0⟧は素晴らしい", mapping: ["⟦0⟧": "Claude Code"])
        #expect(result.text == "Claude Codeは素晴らしい")
        #expect(result.unresolvedTokens.isEmpty)
    }

    // MARK: - 寛容パス（崩れトークン復元）

    @Test func unmaskRecoversFullWidthDigits() {
        let result = TermProtector.unmask("⟦０⟧は素晴らしい", mapping: ["⟦0⟧": "Claude"])
        #expect(result.text == "Claudeは素晴らしい")
        #expect(result.unresolvedTokens.isEmpty)
    }

    @Test func unmaskRecoversBracketizedToken() {
        // 翻訳エンジンが ⟦⟧ を [] に置き換えるケース
        let result = TermProtector.unmask("[0]は素晴らしい", mapping: ["⟦0⟧": "Claude"])
        #expect(result.text == "Claudeは素晴らしい")
        #expect(result.unresolvedTokens.isEmpty)
    }

    @Test func unmaskRecoversDoubledBrackets() {
        let result = TermProtector.unmask("[[1]] と ⟦0⟧", mapping: ["⟦0⟧": "MCP", "⟦1⟧": "Claude"])
        #expect(result.text == "Claude と MCP")
        #expect(result.unresolvedTokens.isEmpty)
    }

    @Test func unmaskRecoversTokenWithSpaces() {
        let result = TermProtector.unmask("⟦ 0 ⟧の話", mapping: ["⟦0⟧": "evals"])
        #expect(result.text == "evalsの話")
        #expect(result.unresolvedTokens.isEmpty)
    }

    @Test func unmaskSkipsOutOfRangeIndices() {
        // mapping にない index（訳文中の正当な [5] 等）は誤食しない
        let result = TermProtector.unmask("文献[5]を参照。⟦0⟧が必要", mapping: ["⟦0⟧": "MCP"])
        #expect(result.text == "文献[5]を参照。MCPが必要")
        #expect(result.unresolvedTokens.isEmpty)
    }

    @Test func unmaskDoesNotRecoverAlreadyResolvedIndex() {
        // ⟦0⟧ が正常復元済みなら、訳文中の [0] は崩れトークンとして扱わない
        let result = TermProtector.unmask("⟦0⟧の配列の[0]番目", mapping: ["⟦0⟧": "MCP"])
        #expect(result.text == "MCPの配列の[0]番目")
        #expect(result.unresolvedTokens.isEmpty)
    }

    // MARK: - glossary 版 mask（訳語指定）

    @Test func glossaryMaskMapsToTargetTerm() {
        let glossary = [KeywordParser.GlossaryEntry(term: "evals", target: "評価")]
        let (masked, mapping) = TermProtector.mask("We run evals daily", glossary: glossary)
        #expect(masked == "We run ⟦0⟧ daily")
        #expect(mapping == ["⟦0⟧": "評価"])
    }

    @Test func glossaryMaskWithoutTargetKeepsSourceForm() {
        let glossary = [KeywordParser.GlossaryEntry(term: "MCP", target: nil)]
        let (masked, mapping) = TermProtector.mask("the mcp server", glossary: glossary)
        #expect(masked == "the ⟦0⟧ server")
        // 訳語未指定はソース上の実際の表記を維持（従来挙動）
        #expect(mapping == ["⟦0⟧": "mcp"])
    }

    @Test func glossaryMaskMixedEntries() {
        let glossary = [
            KeywordParser.GlossaryEntry(term: "Claude Code", target: nil),
            KeywordParser.GlossaryEntry(term: "evals", target: "評価"),
        ]
        let (masked, mapping) = TermProtector.mask("Claude Code runs evals", glossary: glossary)
        #expect(masked == "⟦0⟧ runs ⟦1⟧")
        #expect(mapping == ["⟦0⟧": "Claude Code", "⟦1⟧": "評価"])
    }

    @Test func glossaryMaskLongestMatchWins() {
        let glossary = [
            KeywordParser.GlossaryEntry(term: "Claude", target: "クロード"),
            KeywordParser.GlossaryEntry(term: "Claude Code", target: nil),
        ]
        let (masked, mapping) = TermProtector.mask("Claude Code is here", glossary: glossary)
        #expect(masked == "⟦0⟧ is here")
        #expect(mapping == ["⟦0⟧": "Claude Code"])
    }

    @Test func glossaryRoundtripReplacesWithTarget() {
        let glossary = [KeywordParser.GlossaryEntry(term: "evals", target: "評価")]
        let (masked, mapping) = TermProtector.mask("evals are key", glossary: glossary)
        // 翻訳後の unmask で訳語に置換される
        #expect(TermProtector.unmask(masked, mapping: mapping).text == "評価 are key")
    }
}
