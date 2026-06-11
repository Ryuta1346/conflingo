import Foundation
import Testing
@testable import ConfLingo

struct KeywordParserTests {
    @Test func parsesCommaSeparatedKeywords() {
        #expect(KeywordParser.parse("Claude, MCP, sub-agent") == ["Claude", "MCP", "sub-agent"])
    }

    @Test func parsesNewlineAndJapaneseComma() {
        #expect(KeywordParser.parse("Claude\nMCP、evals") == ["Claude", "MCP", "evals"])
    }

    @Test func trimsWhitespace() {
        #expect(KeywordParser.parse("  Claude Code  ,  MCP  ") == ["Claude Code", "MCP"])
    }

    @Test func dropsEmptyEntries() {
        #expect(KeywordParser.parse("Claude,,, ,MCP,") == ["Claude", "MCP"])
    }

    @Test func deduplicatesCaseInsensitivelyKeepingFirst() {
        #expect(KeywordParser.parse("MCP, mcp, Claude, CLAUDE") == ["MCP", "Claude"])
    }

    @Test func emptyInputReturnsEmptyArray() {
        #expect(KeywordParser.parse("").isEmpty)
        #expect(KeywordParser.parse("  \n ").isEmpty)
    }

    @Test func defaultKeywordsAreValid() {
        let parsed = KeywordParser.parse(KeywordParser.defaultKeywords)
        #expect(parsed.count > 10)
        #expect(parsed.contains("Claude Code"))
        #expect(parsed.contains("MCP"))
    }

    // MARK: - parseGlossary（term=訳語）

    @Test func glossaryParsesTargetAfterEquals() {
        let entries = KeywordParser.parseGlossary("evals=評価, MCP")
        #expect(entries == [
            KeywordParser.GlossaryEntry(term: "evals", target: "評価"),
            KeywordParser.GlossaryEntry(term: "MCP", target: nil),
        ])
    }

    @Test func glossarySupportsFullWidthEquals() {
        let entries = KeywordParser.parseGlossary("token＝トークン")
        #expect(entries == [KeywordParser.GlossaryEntry(term: "token", target: "トークン")])
    }

    @Test func glossarySplitsOnFirstEqualsOnly() {
        let entries = KeywordParser.parseGlossary("a=b=c")
        #expect(entries == [KeywordParser.GlossaryEntry(term: "a", target: "b=c")])
    }

    @Test func glossaryEmptyTargetBecomesNil() {
        let entries = KeywordParser.parseGlossary("Claude= , MCP=")
        #expect(entries == [
            KeywordParser.GlossaryEntry(term: "Claude", target: nil),
            KeywordParser.GlossaryEntry(term: "MCP", target: nil),
        ])
    }

    @Test func glossaryTrimsAroundEquals() {
        let entries = KeywordParser.parseGlossary("fine-tuning = ファインチューニング")
        #expect(entries == [KeywordParser.GlossaryEntry(term: "fine-tuning", target: "ファインチューニング")])
    }

    @Test func glossaryDeduplicatesByTermKeepingFirst() {
        let entries = KeywordParser.parseGlossary("MCP=エムシーピー, mcp=別訳")
        #expect(entries == [KeywordParser.GlossaryEntry(term: "MCP", target: "エムシーピー")])
    }

    @Test func glossaryDropsEntriesWithEmptyTerm() {
        let entries = KeywordParser.parseGlossary("=訳語だけ, Claude")
        #expect(entries == [KeywordParser.GlossaryEntry(term: "Claude", target: nil)])
    }

    @Test func parseDelegatesToGlossaryTerms() {
        // 既存の parse は term のみ返す（contextualStrings 用）
        #expect(KeywordParser.parse("evals=評価, MCP") == ["evals", "MCP"])
    }
}
