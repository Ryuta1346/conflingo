import CryptoKit
import Foundation
@testable import ConfLingo

@MainActor
struct RAGBudgetTransport: InsightHTTPTransport {
    let caseID: String
    let ledger: RAGBudgetLedger
    var downstream: any InsightHTTPTransport = URLSessionInsightTransport()
    var count: @MainActor (URLRequest) async throws -> Data = RAGCountHTTP.send

    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        let expected = "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse"
        guard request.url?.absoluteString == expected, request.httpMethod == "POST",
              let data = request.httpBody,
              var body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let config = body["generationConfig"] as? [String: Any], config["maxOutputTokens"] as? Int == 8_192,
              (config["thinkingConfig"] as? [String: String])?["thinkingLevel"] == "medium" else { throw RAGEvaluationError.configuration }
        let canonical = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        let hash = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        body["model"] = "models/gemini-3.8-flash"
        var counter = request
        counter.url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:countTokens")
        counter.setValue("application/json", forHTTPHeaderField: "Accept")
        counter.httpBody = try JSONSerialization.data(withJSONObject: ["generateContentRequest": body])
        try Task.checkCancellation()
        try ledger.begin(caseID: caseID, operation: .count, hash: hash, reservation: 0)
        let response = try await count(counter)
        let counted = try JSONDecoder().decode(TokenCount.self, from: response).totalTokens
        try ledger.completeCount(caseID: caseID, tokens: counted)
        try Task.checkCancellation()
        // Reserve the full approved input allowance, including schema/framing overhead.
        let reservation = RAGBudgetLedger.cost(input: 6_000, output: 8_192, thinking: 0) * 1.2
        try ledger.begin(caseID: caseID, operation: .generate, hash: hash, reservation: reservation)
        var decoder = LLMStreamDecoder(provider: .gemini)
        try await downstream.stream(request) { chunk in
            try decoder.consume(chunk)
            try receive(chunk)
        }
        let result = try decoder.finish()
        try ledger.completeGeneration(caseID: caseID, usage: result.usage)
    }

    private struct TokenCount: Decodable { let totalTokens: Int }
}

enum RAGCountHTTP {
    @MainActor static func send(_ request: URLRequest) async throws -> Data {
        guard request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:countTokens" else {
            throw RAGEvaluationError.configuration
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw RAGEvaluationError.response }
        var result = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard result.count < 65_536 else { throw RAGEvaluationError.response }
            result.append(byte)
        }
        return result
    }
}
