import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMUnifiedStreamTests {
    @Test func selectedGeminiUsesConfiguredModelAndSingleKeyRead() async throws {
        var connection = LLMConnection.preset(.gemini)
        connection.model = "synthetic-model"
        let http = FakeInsightHTTP()
        http.chunks = [try geminiSSE(payload: #"{"text":"回答🙂","kind":"answerSuggestion","evidenceIDs":[]}"#)]
        var keyReads = 0
        let client = LLMInsightClient(connection: connection, key: { keyReads += 1; return "synthetic-key" }, transport: http)
        let request = try InsightRequest(sessionID: UUID(), question: "質問", trigger: .manual, events: [], purpose: .summary)
        let result = try await client.generate(request) { _ in }
        #expect(result.text == "回答🙂")
        #expect(keyReads == 1)
        let sent = try #require(http.requests.first)
        #expect(http.requests.count == 1)
        #expect(sent.url?.path == "/v1beta/models/synthetic-model:streamGenerateContent")
        #expect(sent.url?.query == "alt=sse")
        #expect(sent.timeoutInterval == 60)
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "synthetic-key")
        let data = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["responseSchema"] != nil)
        #expect(generation["thinkingConfig"] == nil)
    }

    @Test func commonDecoderAcceptsGeminiAndTrailingUsage() throws {
        let payload = #"{"text":"回答🙂","kind":"answerSuggestion","evidenceIDs":[]}"#
        let stream = try geminiSSE(payload: payload) + Data("data: {\"usageMetadata\":{\"promptTokenCount\":7,\"candidatesTokenCount\":9,\"thoughtsTokenCount\":2}}\n\ndata: [DONE]".utf8)
        var decoder = LLMStreamDecoder(provider: .gemini)
        for byte in stream { try decoder.consume(Data([byte])) }
        let result = try decoder.finish()
        #expect(result.text == "回答🙂")
        #expect(result.usage == InsightUsage(inputTokens: 7, outputTokens: 9, thinkingTokens: 2))
    }

    @Test(arguments: LLMProvider.allCases)
    func cancelledRequestNeverPublishesLateChunk(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "synthetic-model"
        if provider == .custom { connection.baseURL = "https://cloud.example/v1" }
        let payload = #"{"text":"late answer","kind":"answerSuggestion","evidenceIDs":[]}"#
        let chunk = try provider == .gemini ? geminiSSE(payload: payload) : llmSSE(provider: provider, payload: payload)
        let http = CancellingStreamTransport(chunk: chunk)
        let request = try InsightRequest(sessionID: UUID(), question: "Question", trigger: .manual, events: [])
        var updates: [String] = []
        let task = Task { @MainActor in
            try await LLMInsightClient(connection: connection, key: { "synthetic-key" }, transport: http)
                .generate(request) { updates.append($0) }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(updates.isEmpty)
    }
}

@MainActor
private struct CancellingStreamTransport: InsightHTTPTransport {
    let chunk: Data
    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        withUnsafeCurrentTask { $0?.cancel() }
        try receive(chunk)
    }
}
