import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct GeminiInsightClientTests {
    @Test func streamingHandlesEveryUTF8ByteAndStructuredEvidence() async throws {
        let event = insightEvent(text: "合成の会話です")
        let request = try InsightRequest(sessionID: event.sessionID, question: "次は？", trigger: .manual, events: [event])
        let transport = FakeInsightHTTP()
        let payload = "{\"text\":\"確認しましょう🙂\",\"kind\":\"followUpQuestion\",\"evidenceIDs\":[\"\(event.id)\"]}"
        transport.chunks = try geminiSSE(payload: payload, split: true).map { Data([$0]) }
        let client = GeminiInsightClient(key: { "test-key-not-real" }, transport: transport)
        var updates: [String] = []
        let result = try await client.generate(request) { updates.append($0) }
        #expect(result.text == "確認しましょう🙂")
        #expect(result.evidenceIDs == [event.id])
        #expect(result.usage == InsightUsage(inputTokens: 10, outputTokens: 20, thinkingTokens: 2))
        #expect(updates.contains("確認しましょう🙂"))
        let sent = try #require(transport.requests.first)
        #expect(sent.url?.host == "generativelanguage.googleapis.com")
        #expect(sent.url?.query == "alt=sse")
        #expect(sent.value(forHTTPHeaderField: "x-goog-api-key") == "test-key-not-real")
        let bodyData = try #require(sent.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["maxOutputTokens"] as? Int == 1024)
        #expect(body["tools"] == nil)
        #expect(!String(decoding: sent.httpBody ?? Data(), as: UTF8.self).contains(request.sessionID.uuidString))
    }

    @Test func missingKeyNeverReachesHTTP() async throws {
        let event = insightEvent(text: String(repeating: "\u{0001}", count: 12_000))
        let request = try InsightRequest(sessionID: event.sessionID, question: "Explain", trigger: .manual, events: [event])
        let transport = FakeInsightHTTP()
        let client = GeminiInsightClient(key: { nil }, transport: transport)
        await #expect(throws: InsightFailure.missingKey) { try await client.generate(request) { _ in } }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: ["MAX_TOKENS", "SAFETY", "RECITATION"])
    func nonSuccessfulFinishCannotBecomeAnswer(reason: String) async throws {
        let transport = FakeInsightHTTP()
        transport.chunks = [try geminiSSE(payload: "{\"text\":\"unfinished\"}", finish: reason)]
        let client = GeminiInsightClient(key: { "test" }, transport: transport)
        let request = try InsightRequest(sessionID: UUID(), question: "Explain", trigger: .manual, events: [])
        await #expect(throws: (any Error).self) { try await client.generate(request) { _ in } }
    }

    @Test func incompleteMalformedDuplicateAndOversizedStreamsFail() async throws {
        let request = try InsightRequest(sessionID: UUID(), question: "Explain", trigger: .manual, events: [])
        let good = try geminiSSE(payload: "{\"text\":\"answer\",\"kind\":\"risk\",\"evidenceIDs\":[]}")
        let missingEnd = Data("data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hello\"}]}}]}\n\n".utf8)
        for invalid in [Data("data: not-json\n\n".utf8), missingEnd, good + good,
                        Data(repeating: 65, count: 262_145)] {
            let transport = FakeInsightHTTP()
            transport.chunks = [invalid]
            let client = GeminiInsightClient(key: { "test" }, transport: transport)
            await #expect(throws: (any Error).self) { try await client.generate(request) { _ in } }
        }
    }

    @Test func providerErrorIsNotRetried() async throws {
        let transport = FakeInsightHTTP()
        transport.failure = InsightFailure.http(429)
        let request = try InsightRequest(sessionID: UUID(), question: "Explain", trigger: .manual, events: [])
        let client = GeminiInsightClient(key: { "test" }, transport: transport)
        await #expect(throws: InsightFailure.http(429)) { try await client.generate(request) { _ in } }
        #expect(transport.requests.count == 1)
    }
}

@MainActor
final class FakeInsightHTTP: InsightHTTPTransport {
    var requests: [URLRequest] = []
    var chunks: [Data] = []
    var failure: (any Error)?
    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        requests.append(request)
        if let failure { throw failure }
        for chunk in chunks { try receive(chunk) }
    }
}

func geminiSSE(payload: String, finish: String = "STOP", split: Bool = false) throws -> Data {
    let pieces = split ? payload.map(String.init) : [payload]
    var data = Data()
    for piece in pieces {
        let frame: [String: Any] = ["candidates": [["index": 0, "content": ["parts": [["text": piece]]]]]]
        data += Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: frame)) + Data("\r\n\r\n".utf8)
    }
    let end: [String: Any] = ["candidates": [["index": 0, "finishReason": finish]],
                              "usageMetadata": ["promptTokenCount": 10, "candidatesTokenCount": 20, "thoughtsTokenCount": 2]]
    data += Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: end)) + Data("\n\n".utf8)
    return data
}
