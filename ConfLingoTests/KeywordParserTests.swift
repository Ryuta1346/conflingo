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
}
