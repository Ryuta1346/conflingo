import Foundation

@MainActor
struct GeminiInsightClient: InsightClient {
    nonisolated static let model = "gemini-3.8-flash"
    let key: () async throws -> String?
    var transport: any InsightHTTPTransport = URLSessionInsightTransport()
    var modelID = Self.model

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        try Task.checkCancellation()
        guard let key = try await key(), !key.isEmpty else { throw InsightFailure.missingKey }
        try Task.checkCancellation()
        let httpRequest = try makeRequest(request, key: key)
        var decoder = GeminiStreamDecoder()
        try await transport.stream(httpRequest) { data in
            try decoder.consume(data)
            if let text = decoder.previewText, !text.isEmpty { update(text) }
        }
        try Task.checkCancellation()
        return try decoder.finish()
    }

    private func makeRequest(_ request: InsightRequest, key: String) throws -> URLRequest {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):streamGenerateContent?alt=sse") else {
            throw InsightFailure.invalidResponse
        }
        let prompt = try InsightPrompt(request)
        var generation: [String: Any] = ["maxOutputTokens": 8192, "responseMimeType": "application/json",
                                          "responseSchema": prompt.geminiSchema]
        if modelID == Self.model { generation["thinkingConfig"] = ["thinkingLevel": "medium"] }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": prompt.instruction]]],
            "contents": [["role": "user", "parts": [["text": prompt.context],
                                                   ["text": prompt.question]]]],
            "generationConfig": generation
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 131_072 else { throw InsightFailure.oversized }
        var result = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeoutSeconds)
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        result.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        result.httpBody = data
        return result
    }
}
