import Foundation
import Testing
import WebKit
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LLMWebResearchTests {
    @Test func searchSuggestionsNavigationDelegateIsInstalled() {
        let coordinator = GoogleSearchSuggestions.Coordinator()
        #expect(coordinator.responds(to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")))
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func japaneseEmojiCitationsRemainClickable(provider: LLMProvider) throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        let card = try LLMResearchResponse.decode(nativeResearchFixture(provider, text: "日本語🧑‍💻の回答。"), provider: provider, request: request)
        let rendered = ResearchAnswerText.attributed(card)
        #expect(String(rendered.characters) == "日本語🧑‍💻の回答。[1]")
        #expect(rendered.runs.contains { $0.link?.absoluteString == "https://example.com/source" })
        #expect(!AssistanceMarkdown.render([card]).contains("[[web:"))
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func incompleteResponseIsRejected(provider: LLMProvider) throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        var object = try #require(JSONSerialization.jsonObject(with: nativeResearchFixture(provider)) as? [String: Any])
        if provider == .gemini {
            var candidates = try #require(object["candidates"] as? [[String: Any]])
            candidates[0]["finishReason"] = "MAX_TOKENS"
            object["candidates"] = candidates
        } else if provider == .openai { object["status"] = "incomplete" }
        else { object["stop_reason"] = "pause_turn" }
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: InsightFailure.invalidResponse) { try LLMResearchResponse.decode(data, provider: provider, request: request) }
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func usesSelectedModelKeyAndNativeSearch(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "selected-model"
        let http = FakeResearchHTTP()
        http.response = try nativeResearchFixture(provider)
        let request = try InsightRequest(sessionID: UUID(), question: "Research this", trigger: .manual, events: [], purpose: .webResearch)
        let answer = try await LLMWebResearchClient(connection: connection, key: { "existing-llm-key" }, transport: http).generate(request)
        let sent = try #require(http.requests.first)
        let body = try #require(JSONSerialization.jsonObject(with: sent.httpBody ?? Data()) as? [String: Any])
        #expect(http.requests.count == 1)
        #expect(sent.url?.host == URL(string: connection.baseURL)?.host)
        #expect(sent.timeoutInterval == 60)
        #expect(body["tools"] != nil)
        #expect(body["response_format"] == nil && body["output_config"] == nil)
        #expect(answer.webReferences?.first?.url.absoluteString == "https://example.com/source")
        #expect(answer.text.contains("[[web:"))
        switch provider {
        case .gemini:
            #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "existing-llm-key")
            #expect(sent.url?.path.hasSuffix("selected-model:generateContent") == true)
            #expect(answer.searchSuggestionsHTML?.contains("Google") == true)
        case .openai:
            #expect(body["model"] as? String == "selected-model")
            #expect(body["max_tool_calls"] as? Int == 1)
            #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer existing-llm-key")
        case .claude:
            #expect(body["model"] as? String == "selected-model")
            #expect((body["tools"] as? [[String: Any]])?.first?["max_uses"] as? Int == 1)
            #expect(sent.value(forHTTPHeaderField: "x-api-key") == "existing-llm-key")
        default: break
        }
    }

    @Test(arguments: [LLMProvider.kimi, .deepseek, .custom, .local])
    func unsupportedConnectionsNeverSend(provider: LLMProvider) async throws {
        let http = FakeResearchHTTP()
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        await #expect(throws: ResearchFailure.unsupported) {
            try await LLMWebResearchClient(connection: .preset(provider), key: { "test" }, transport: http).generate(request)
        }
        #expect(http.requests.isEmpty)
    }

    @Test(arguments: [LLMProvider.gemini, .openai, .claude])
    func citationlessOrUnfinishedResponsesAreNotResearch(provider: LLMProvider) async throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        let data = try nativeResearchFixture(provider, cited: false)
        #expect(throws: ResearchFailure.noSources) { try LLMResearchResponse.decode(data, provider: provider, request: request) }
    }

    @Test func localCitationsAreValidatedAndSavedWithWebSources() throws {
        let session = UUID()
        let event = TranscriptEvent(id: UUID(), sessionID: session, origin: .microphone, languageCode: "ja",
            startOffset: 1, endOffset: 2, text: "資料と比較", isFinal: true, revision: 1, sourceStartTime: 1)
        let request = try InsightRequest(sessionID: session, question: "topic", trigger: .manual, events: [event])
        let data = try nativeResearchFixture(.claude, text: "Finding [[speech:\(event.id)]]")
        let card = try LLMResearchResponse.decode(data, provider: .claude, request: request)
        #expect(card.evidenceIDs == [event.id])
        #expect(!card.text.contains("[[speech:"))
        #expect(try JSONDecoder().decode(MeetingInsight.self, from: JSONEncoder().encode(card)) == card)
        let invalid = try nativeResearchFixture(.claude, text: "Finding [[speech:\(UUID())]]")
        #expect(throws: InsightFailure.invalidResponse) { try LLMResearchResponse.decode(invalid, provider: .claude, request: request) }
        #expect(AssistanceMarkdown.render([card]).contains("https://example.com/source"))
    }

    @Test func unsafeProviderURLIsRejected() throws {
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        let data = try nativeResearchFixture(.openai, url: "javascript:alert(1)")
        #expect(throws: InsightFailure.invalidResponse) { try LLMResearchResponse.decode(data, provider: .openai, request: request) }
    }
}

@MainActor final class FakeResearchHTTP: ResearchHTTPTransport {
    var requests: [URLRequest] = []
    var response = Data()
    func fetch(_ request: URLRequest) async throws -> Data { requests.append(request); return response }
}

func nativeResearchFixture(_ provider: LLMProvider, cited: Bool = true, text: String = "Finding", url: String = "https://example.com/source") throws -> Data {
    let value: [String: Any]
    switch provider {
    case .gemini:
        value = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": text]]], "groundingMetadata": [
            "webSearchQueries": ["topic"], "searchEntryPoint": ["renderedContent": "<div>Google search suggestions</div>"],
            "groundingChunks": [["web": ["uri": url, "title": "Source"]]],
            "groundingSupports": cited ? [["segment": ["startIndex": 0, "endIndex": text.utf8.count, "text": text], "groundingChunkIndices": [0]]] : []
        ]]]]
    case .openai:
        value = ["status": "completed", "output": [
            ["type": "web_search_call", "status": "completed"],
            ["type": "message", "content": [["type": "output_text", "text": text, "annotations": cited ? [
                ["type": "url_citation", "start_index": 0, "end_index": text.unicodeScalars.count, "url": url, "title": "Source"]
            ] : []]]]
        ]]
    default:
        value = ["stop_reason": "end_turn", "content": [
            ["type": "server_tool_use", "name": "web_search", "id": "search1"],
            ["type": "web_search_tool_result", "tool_use_id": "search1", "content": [["type": "web_search_result", "url": url, "title": "Source"]]],
            ["type": "text", "text": text, "citations": cited ? [["type": "web_search_result_location", "url": url, "title": "Source", "cited_text": "source excerpt"]] : []]
        ]]
    }
    return try JSONSerialization.data(withJSONObject: value)
}
