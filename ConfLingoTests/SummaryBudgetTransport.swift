import CryptoKit
import Foundation
@testable import ConfLingo

@MainActor
struct SummaryBudgetTransport: InsightHTTPTransport {
    let caseID: String
    let ledger: SummaryBudgetLedger
    var downstream: any InsightHTTPTransport = URLSessionInsightTransport()
    var timing: SummaryTiming?
    var count: @MainActor (URLRequest) async throws -> Data = RAGCountHTTP.send

    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        timing?.mark(.transport)
        let expected = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse"
        guard request.url?.absoluteString == expected, request.httpMethod == "POST",
              let data = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = body["generationConfig"] as? [String: Any], config["maxOutputTokens"] as? Int == 8_192,
              (config["thinkingConfig"] as? [String: String])?["thinkingLevel"] == "medium" else { throw SummaryEvaluationError.configuration }
        let canonical = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        let hash = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        body["model"] = "models/gemini-3.8-flash"
        var counter = request
        counter.url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:countTokens")
        counter.setValue("application/json", forHTTPHeaderField: "Accept")
        counter.httpBody = try JSONSerialization.data(withJSONObject: ["generateContentRequest": body])
        try Task.checkCancellation()
        try ledger.begin(caseID: caseID, operation: .count, hash: hash, reservation: 0)
        timing?.mark(.countStart)
        let response = try await count(counter)
        timing?.mark(.countEnd)
        let counted = try JSONDecoder().decode(TokenCount.self, from: response).totalTokens
        try ledger.completeCount(caseID: caseID, tokens: counted)
        try Task.checkCancellation()
        // Reserve the full approved input allowance, including schema/framing overhead.
        let reservation = SummaryBudgetLedger.reservation
        try ledger.begin(caseID: caseID, operation: .generate, hash: hash, reservation: reservation)
        var decoder = GeminiStreamDecoder()
        timing?.mark(.generationStart)
        try await downstream.stream(request) { chunk in
            timing?.receive(bytes: chunk.count)
            try decoder.consume(chunk)
            try receive(chunk)
        }
        timing?.mark(.streamEnd)
        let result = try decoder.finish()
        try ledger.completeGeneration(caseID: caseID, usage: result.usage)
        timing?.mark(.usageSettled)
    }

    private struct TokenCount: Decodable { let totalTokens: Int }
}
