import Foundation
import Testing
@testable import ConfLingo

struct InsightPayloadPreviewTests {
    @Test(arguments: [
        #"{"text":"回答"#,
        #"{"kind":"answerSuggestion","text":"回答"#,
        #"{"evidenceIDs":[],"kind":"answerSuggestion","text":"回答"#,
        #"{"metadata":{"text":"別の値"},"items":[{"text":"入れ子"}],"text":"回答"#,
        #"{"supplement":"引用: \"text\":\"別の値\" } [","text":"回答"#,
        #"{"kind":"answerSuggestion","te\u0078t":"回答"#
    ])
    func previewsTopLevelTextRegardlessOfKeyOrder(content: String) {
        #expect(InsightPayload.preview(content) == "回答")
    }

    @Test(arguments: [
        #"{"metadata":{"text":"入れ子"}}"#,
        #"{"items":[{"text":"入れ子"}]}"#,
        #"{"supplement":"引用: \"text\":\"別の値\""}"#,
        #"{"kind":"answerSuggestion","text""#,
        #"{"kind":"answerSuggestion","text":null}"#,
        #"[{"text":"配列"}]"#
    ])
    func waitsForTopLevelStringValue(content: String) {
        #expect(InsightPayload.preview(content) == nil)
    }

    @Test func waitsForCompleteEscapesAndSurrogatePairs() {
        let prefix = #"{"kind":"answerSuggestion","text":"確認\n\"引用\"\\ "#
        #expect(InsightPayload.preview(prefix) == "確認\n\"引用\"\\ ")
        #expect(InsightPayload.preview(prefix + #"\uD83"#) == nil)
        #expect(InsightPayload.preview(prefix + #"\uD83D\uDE"#) == nil)
        #expect(InsightPayload.preview(prefix + #"\uD83D\uDE42"#) == "確認\n\"引用\"\\ 🙂")
        #expect(InsightPayload.preview(prefix + #"\uD83D\uDE42","evidenceIDs":[]}"#) == "確認\n\"引用\"\\ 🙂")
    }
}

@MainActor
struct LLMPreviewIntegrationTests {
    @Test(arguments: [LLMProvider.openai, .claude, .custom])
    func deliversReorderedTextBeforeStreamCompletion(provider: LLMProvider) async throws {
        var connection = LLMConnection.preset(provider)
        connection.model = "test-model"
        if provider == .custom { connection.baseURL = "https://cloud.example/v1" }
        let transport = FakeInsightHTTP()
        // No terminal event: any observed update must arrive before completion.
        transport.chunks = try llmSSE(provider: provider,
                                      payload: #"{"kind":"answerSuggestion","evidenceIDs":[],"text":"途中🙂"#,
                                      complete: false).map { Data([$0]) }
        let request = try InsightRequest(sessionID: UUID(), question: "説明して", trigger: .manual, events: [])
        var updates: [String] = []
        await #expect(throws: InsightFailure.invalidResponse) {
            try await LLMInsightClient(connection: connection, key: { "synthetic-key" }, transport: transport)
                .generate(request) { updates.append($0) }
        }
        #expect(updates.contains("途中🙂"))
    }

    @Test func geminiAlsoPreviewsReorderedTextBeforeCompletion() throws {
        let payload = #"{"kind":"answerSuggestion","evidenceIDs":[],"text":"途中🙂"#
        let frame: [String: Any] = ["candidates": [["content": ["parts": [["text": payload]]]]]]
        let data = Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: frame)) + Data("\n\n".utf8)
        var decoder = LLMStreamDecoder(provider: .gemini)
        for byte in data { try decoder.consume(Data([byte])) }
        #expect(decoder.previewText == "途中🙂")
        #expect(throws: InsightFailure.invalidResponse) { try decoder.finish() }
    }
}
