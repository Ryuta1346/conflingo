import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMClientTests {
    @Test(arguments: [LLMProvider.openai, .claude, .kimi, .deepseek, .custom, .local])
    func routesRequestAndDecodesFragmentedResponse(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "test-model"
        if provider == .custom { connection.baseURL = "https://cloud.example/prefix/v1" }
        let event = insightEvent()
        let request = try InsightRequest(sessionID: event.sessionID, question: "説明して", trigger: .manual, events: [event])
        let transport = FakeInsightHTTP()
        let payload = "{\"text\":\"確認します🙂\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[\"\(event.id)\"]}"
        transport.chunks = try llmSSE(provider: provider, payload: payload).map { Data([$0]) }
        let client = LLMInsightClient(connection: connection, key: { provider == .local ? nil : "synthetic-key" }, transport: transport)
        var updates: [String] = []
        let result = try await client.generate(request) { updates.append($0) }
        #expect(result.text == "確認します🙂")
        #expect(result.evidenceIDs == [event.id])
        #expect(updates.contains("確認します🙂"))
        let sent = try #require(transport.requests.first)
        let data = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "test-model")
        #expect(transport.requests.count == 1)
        if provider == .local { #expect(sent.value(forHTTPHeaderField: "Authorization") == nil) }
        else if provider == .claude {
            #expect(sent.value(forHTTPHeaderField: "x-api-key") == "synthetic-key")
            #expect(sent.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(body["output_config"] != nil)
        } else { #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-key") }
        if provider == .openai {
            #expect(sent.url?.path == "/v1/responses")
            #expect(body["store"] as? Bool == false)
            #expect(body["text"] != nil)
        }
        if [.kimi, .deepseek].contains(provider) {
            #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
        }
    }

    @Test(arguments: [LLMProvider.openai, .claude, .custom])
    func incompleteStreamsNeverProduceSuccessfulCards(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "test"
        if provider == .custom { connection.baseURL = "https://cloud.example/v1" }
        let transport = FakeInsightHTTP()
        transport.chunks = [try llmSSE(provider: provider, payload: "{\"text\":\"partial\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}", complete: false)]
        let request = try InsightRequest(sessionID: UUID(), question: "Question", trigger: .manual, events: [])
        await #expect(throws: InsightFailure.invalidResponse) {
            try await LLMInsightClient(connection: connection, key: { "key" }, transport: transport).generate(request) { _ in }
        }
    }

    @Test func schemaAndPromptModesAreExplicitAndDoNotRetry() async throws {
        let request = try InsightRequest(sessionID: UUID(), question: "Question", trigger: .manual, events: [])
        for format in LLMOutputFormat.allCases {
            var connection = LLMConnection.preset(.local)
            connection.model = "qwen-test"
            connection.outputFormat = format
            let transport = FakeInsightHTTP()
            transport.chunks = [try llmSSE(provider: .local, payload: "not JSON")]
            do {
                _ = try await LLMInsightClient(connection: connection, key: { nil }, transport: transport).generate(request) { _ in }
                Issue.record("Malformed output must fail")
            } catch {}
            #expect(transport.requests.count == 1)
            let data = try #require(transport.requests.first?.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect((body["response_format"] == nil) == (format == .prompt))
        }
    }
}

func llmSSE(provider: LLMProvider, payload: String, complete: Bool = true) throws -> Data {
    func frame(_ object: [String: Any]) throws -> String {
        "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n\n"
    }
    var result: String
    if provider == .openai {
        result = try frame(["type": "response.output_text.delta", "delta": payload])
        if complete { result += try frame(["type": "response.completed", "response": ["status": "completed"]]) }
    } else if provider == .claude {
        result = try frame(["type": "message_start", "message": ["usage": ["input_tokens": 5, "output_tokens": 0]]])
        result += try frame(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": payload]])
        if complete {
            result += try frame(["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": 8]])
            result += try frame(["type": "message_stop"])
        }
    } else {
        result = try frame(["choices": [["index": 0, "delta": ["reasoning_content": "not answer", "content": payload], "finish_reason": NSNull()]]])
        if complete {
            result += try frame(["choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]])
            result += "data: [DONE]\n\n"
        }
    }
    return Data(result.utf8)
}

@MainActor
struct LLMProtocolBoundaryTests {
    @Test(arguments: [LLMProvider.openai, .claude, .kimi, .deepseek, .local])
    func summaryDocumentsAndAnswerLanguageSurviveEveryAdapter(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "test-model"
        let ref = reference()
        let event = insightEvent()
        let request = try InsightRequest(sessionID: event.sessionID, question: "Summarize", trigger: .manual,
                                        events: [event], answerLanguage: .english, knowledge: [ref], purpose: .summary)
        let payload = "{\"text\":\"Spoken fact\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[\"\(event.id)\"],\"knowledgeIDs\":[\"\(ref.id)\"],\"supplement\":\"Document fact\"}"
        let http = FakeInsightHTTP()
        http.chunks = [try llmSSE(provider: provider, payload: payload)]
        let result = try await LLMInsightClient(connection: connection, key: { "key" }, transport: http).generate(request) { _ in }
        let card = try result.card(for: request)
        #expect(card.knowledgeReferences == [ref])
        #expect(result.supplement == "Document fact")
        let sent = try #require(http.requests.first)
        #expect(sent.timeoutInterval == 60)
        let data = try #require(sent.httpBody)
        let body = String(decoding: data, as: UTF8.self)
        #expect(body.contains("answerLanguage"))
        #expect(body.contains("SUMMARY CONTRACT"))
        #expect(body.contains(ref.id.uuidString))
        #expect(!body.contains(ref.documentID.uuidString))
        #expect(!body.contains(request.sessionID.uuidString))
    }

    @Test(arguments: [LLMProvider.openai, .claude, .local])
    func terminalFailureCannotBeHiddenByValidJSON(provider: LLMProvider) throws {
        let payload = #"{"text":"answer","kind":"answerSuggestion","evidenceIDs":[]}"#
        var decoder = LLMStreamDecoder(provider: provider)
        try decoder.consume(llmSSE(provider: provider, payload: payload, complete: false))
        let failure: String
        if provider == .openai { failure = #"{"type":"response.failed","response":{"status":"failed"}}"# }
        else if provider == .claude { failure = #"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"# }
        else { failure = #"{"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"# }
        #expect(throws: (any Error).self) { try decoder.consume(Data("data: \(failure)\n\n".utf8)) }
    }

    @Test func openAIReasoningItemBeforeTextDoesNotHideAnswerAndUsageIsNotDoubleCounted() throws {
        let payload = #"{"text":"answer","kind":"answerSuggestion","evidenceIDs":[]}"#
        let delta: [String: Any] = ["type": "response.output_text.delta", "output_index": 1, "content_index": 0, "delta": payload]
        var stream = Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: delta)) + Data("\n\n".utf8)
        stream += Data(#"data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":5,"output_tokens":10,"output_tokens_details":{"reasoning_tokens":4}}}}"#.utf8)
        stream += Data("\n\n".utf8)
        var decoder = LLMStreamDecoder(provider: .openai)
        try decoder.consume(stream)
        let result = try decoder.finish()
        #expect(result.text == "answer")
        #expect(result.usage == InsightUsage(inputTokens: 5, outputTokens: 6, thinkingTokens: 4))
    }

    @Test func endpointPolicyRejectsOtherHostsPortsAndPathPrefixes() throws {
        let base = try #require(URL(string: "https://cloud.example/tenant/v1"))
        for value in ["https://other.example/tenant/v1/chat/completions", "https://cloud.example:8443/tenant/v1/models", "https://cloud.example/tenant/v10/models", "http://cloud.example/tenant/v1/models"] {
            let url = try #require(URL(string: value))
            #expect(!URLSessionInsightTransport.permits(url, base: base))
        }
        let allowed = try #require(URL(string: "https://cloud.example/tenant/v1/models"))
        #expect(URLSessionInsightTransport.permits(allowed, base: base))
    }
}
