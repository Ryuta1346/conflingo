import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ClaudeResearchResponseTests {
    struct Sentence: Sendable {
        let prefix: String
        let claim: String
        let suffix: String
        let expected: String
    }

    private let firstURL = "https://example.com/first"
    private let secondURL = "https://example.com/second"

    @Test(arguments: [
        Sentence(prefix: "Based on the results, ", claim: "Swift", suffix: " handles Unicode.",
                 expected: "Based on the results, Swift[1] handles Unicode."),
        Sentence(prefix: "調査結果では、", claim: "日本語🧑‍💻", suffix: "にも対応しています。",
                 expected: "調査結果では、日本語🧑‍💻[1]にも対応しています。")
    ])
    func citationBlocksDoNotSplitSentences(sentence: Sentence) throws {
        let answer = try decode([
            text(sentence.prefix), text(sentence.claim, citing: firstURL), text(sentence.suffix)
        ])
        #expect(String(ResearchAnswerText.attributed(answer).characters) == sentence.expected)
    }

    @Test(arguments: ["", " ", "\t", "\n", "\n\n"])
    func originalWhitespaceAndEmptyBlocksArePreserved(separator: String) throws {
        let answer = try decode([
            text("First", citing: firstURL), text(separator), text("Second", citing: secondURL)
        ])
        #expect(String(ResearchAnswerText.attributed(answer).characters) == "First[1]\(separator)Second[2]")
    }

    @Test func repeatedCitationsKeepTheirPositionsThroughPersistenceAndMarkdown() throws {
        let answer = try decode([
            text("最初の主張", citing: firstURL), text("と次の主張", citing: secondURL),
            text("、同じ出典での補足。", citing: firstURL), text("\n\n次の段落です。")
        ])
        let restored = try JSONDecoder().decode(MeetingInsight.self, from: JSONEncoder().encode(answer))
        #expect(restored == answer)
        #expect(restored.webReferences?.map { $0.url.absoluteString } == [firstURL, secondURL])
        let rendered = ResearchAnswerText.attributed(restored)
        #expect(String(rendered.characters) == "最初の主張[1]と次の主張[2]、同じ出典での補足。[1]\n\n次の段落です。")
        #expect(rendered.runs.compactMap { $0.link?.absoluteString } == [firstURL, secondURL, firstURL])
        let markdown = AssistanceMarkdown.render([restored])
        #expect(markdown.contains("> 最初の主張[1](<\(firstURL)>)と次の主張[2](<\(secondURL)>)、同じ出典での補足。[1](<\(firstURL)>)\n> \n> 次の段落です。"))
        #expect(!markdown.contains("[[web:"))
    }

    @Test(arguments: ["https://example.com/unknown", "javascript:alert(1)"])
    func laterBlockCannotCiteAnUnknownSource(url: String) throws {
        #expect(throws: InsightFailure.invalidResponse) {
            try decode([text("Valid", citing: firstURL), text("Invalid", citing: url)])
        }
    }

    private func text(_ value: String, citing url: String? = nil) -> [String: Any] {
        var block: [String: Any] = ["type": "text", "text": value]
        if let url {
            block["citations"] = [["type": "web_search_result_location", "url": url, "title": "Source", "cited_text": "excerpt"]]
        }
        return block
    }

    private func decode(_ blocks: [[String: Any]]) throws -> MeetingInsight {
        let content: [[String: Any]] = [
            ["type": "server_tool_use", "name": "web_search", "id": "search1"],
            ["type": "web_search_tool_result", "tool_use_id": "search1", "content": [
                ["type": "web_search_result", "url": firstURL, "title": "First source"],
                ["type": "web_search_result", "url": secondURL, "title": "Second source"]
            ]]
        ] + blocks
        let data = try JSONSerialization.data(withJSONObject: ["stop_reason": "end_turn", "content": content])
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [], purpose: .webResearch)
        return try LLMResearchResponse.decode(data, provider: .claude, request: request)
    }
}
