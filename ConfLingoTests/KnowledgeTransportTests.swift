import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KnowledgeTransportTests {
    @Test func sendsOnlyReferenceSnapshotAndValidatesReturnedIDs() async throws {
        let ref = reference("料金.md")
        let request = try InsightRequest(sessionID: UUID(), question: "料金？", trigger: .manual, events: [], knowledge: [ref])
        let transport = FakeInsightHTTP()
        let payload = "{\"text\":\"100円\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[],\"knowledgeIDs\":[\"\(ref.id)\"]}"
        transport.chunks = [try geminiSSE(payload: payload)]
        let client = GeminiInsightClient(key: { "synthetic-key" }, transport: transport)
        let result = try await client.generate(request) { _ in }
        #expect(result.knowledgeIDs == [ref.id])
        #expect(try result.card(for: request).knowledgeReferences == [ref])
        let data = try #require(transport.requests.first?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try #require(body["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: String]])
        let contextText = try #require(parts.first?["text"])
        let context = try #require(JSONSerialization.jsonObject(with: Data(contextText.utf8)) as? [String: Any])
        let refs = try #require(context["documents"] as? [[String: Any]])
        #expect(refs.count == 1)
        #expect(Set(refs[0].keys) == ["id", "title", "location", "text"])
        #expect(refs[0]["text"] as? String == ref.snippet)
        #expect(!String(decoding: data, as: UTF8.self).contains(ref.documentID.uuidString))
        #expect(!String(decoding: data, as: UTF8.self).contains(request.sessionID.uuidString))
    }

    @Test func malformedDocumentIDCannotDisappearSilently() async throws {
        let ref = reference()
        let request = try InsightRequest(sessionID: UUID(), question: "料金", trigger: .manual, events: [], knowledge: [ref])
        let transport = FakeInsightHTTP()
        transport.chunks = [try geminiSSE(payload: "{\"text\":\"answer\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[],\"knowledgeIDs\":[\"not-an-id\"]}")]
        await #expect(throws: (any Error).self) {
            try await GeminiInsightClient(key: { "synthetic" }, transport: transport).generate(request) { _ in }
        }
    }

    @Test func absentDocumentFieldIsAllowedForTranscriptOnlyRequests() async throws {
        let request = try InsightRequest(sessionID: UUID(), question: "料金", trigger: .manual, events: [])
        let transport = FakeInsightHTTP()
        transport.chunks = [try geminiSSE(payload: "{\"text\":\"unknown\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}")]
        let result = try await GeminiInsightClient(key: { "synthetic" }, transport: transport).generate(request) { _ in }
        #expect(result.knowledgeIDs.isEmpty)
        #expect(try result.card(for: request).knowledgeReferences.isEmpty)
    }
}
