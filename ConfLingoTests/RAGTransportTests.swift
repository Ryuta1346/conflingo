import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct RAGTransportTests {
    @Test func countReceivesFullProductRequestAndReservationPrecedesBothSends() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try RAGBudgetLedger(url: directory.appendingPathComponent("ledger.json"))
        var counted: [String: Any] = [:]
        let downstream = FakeInsightHTTP()
        downstream.chunks = [try geminiSSE(payload: "{\"text\":\"1200円です\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}")]
        let transport = RAGBudgetTransport(caseID: "R01-ja", ledger: ledger, downstream: downstream) { request in
            #expect(ledger.entries.count == 1)
            #expect(ledger.entries.last?.state == "reserved")
            #expect(request.url?.path.hasSuffix(":countTokens") == true)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            counted = try #require(body["generateContentRequest"] as? [String: Any])
            return Data("{\"totalTokens\":2000}".utf8)
        }
        let sample = RAGEvaluationCase(number: 1, japanese: true)
        _ = try await GeminiInsightClient(key: { "synthetic-key" }, transport: transport).generate(try await sample.request()) { _ in }
        #expect(ledger.entries.count == 2)
        #expect(ledger.entries.last?.state == "complete")
        #expect(counted.removeValue(forKey: "model") as? String == "models/gemini-3.8-flash")
        let sent = try #require(downstream.requests.first?.httpBody)
        let expected = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: sent), options: .sortedKeys)
        #expect(try JSONSerialization.data(withJSONObject: counted, options: .sortedKeys) == expected)
    }

    @Test(arguments: ["count-failure", "oversize", "budget", "generation-failure"])
    func preflightFailuresNeverSendGenerationAndFailuresNeverRetry(reason: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try RAGBudgetLedger(url: directory.appendingPathComponent("ledger.json"), budget: reason == "budget" ? 0.001 : 2)
        let downstream = FakeInsightHTTP()
        downstream.failure = InsightFailure.offline
        var counts = 0
        let transport = RAGBudgetTransport(caseID: "R01-ja", ledger: ledger, downstream: downstream) { _ in
            counts += 1
            if reason == "count-failure" { throw InsightFailure.offline }
            return Data((reason == "oversize" ? "{\"totalTokens\":6001}" : "{\"totalTokens\":2000}").utf8)
        }
        let request = try await RAGEvaluationCase(number: 1, japanese: true).request()
        let client = GeminiInsightClient(key: { "synthetic" }, transport: transport)
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) { try await client.generate(request) { _ in } }
        }
        #expect(counts == 1)
        #expect(downstream.requests.count == (reason == "generation-failure" ? 1 : 0))
        if reason == "generation-failure" { #expect(ledger.spent > 0) }
    }
}
