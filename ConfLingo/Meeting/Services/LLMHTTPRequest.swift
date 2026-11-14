import Foundation

enum LLMHTTPRequest {
    static func make(connection: LLMConnection, path: String, body: [String: Any], key: String?,
                     timeout: TimeInterval, streaming: Bool, queryItems: [URLQueryItem] = []) throws -> URLRequest {
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 131_072 else { throw InsightFailure.oversized }
        let endpoint = try connection.endpoint(path)
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw InsightFailure.invalidEndpoint }
        if !queryItems.isEmpty { parts.queryItems = queryItems }
        guard let url = parts.url else { throw InsightFailure.invalidEndpoint }
        var result = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue(streaming ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        connection.authenticate(&result, key: key)
        result.httpBody = data
        return result
    }
}

extension LLMConnection {
    func authenticate(_ request: inout URLRequest, key: String?) {
        if provider == .claude { request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        guard let key, !key.isEmpty else { return }
        switch provider {
        case .gemini: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .claude: request.setValue(key, forHTTPHeaderField: "x-api-key")
        default: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }
}
