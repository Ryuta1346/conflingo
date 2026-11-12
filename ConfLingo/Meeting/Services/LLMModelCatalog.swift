import Foundation

struct LLMModel: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
protocol LLMCatalogTransport {
    func data(_ request: URLRequest, connection: LLMConnection) async throws -> Data
}

@MainActor
struct URLSessionLLMCatalogTransport: LLMCatalogTransport {
    var configuration: URLSessionConfiguration = .ephemeral
    func data(_ request: URLRequest, connection: LLMConnection) async throws -> Data {
        let base = try connection.endpoint("")
        guard let url = request.url, URLSessionInsightTransport.permits(url, base: base) else { throw InsightFailure.invalidEndpoint }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw InsightFailure.invalidResponse }
        guard response.statusCode == 200 else { throw InsightFailure.http(response.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            guard data.count <= 2_097_152 else { throw InsightFailure.oversized }
        }
        return data
    }
}

@MainActor
struct LLMModelCatalog {
    var transport: any LLMCatalogTransport = URLSessionLLMCatalogTransport()

    func models(for connection: LLMConnection, key: String?) async throws -> [LLMModel] {
        var request = URLRequest(url: try connection.endpoint("models"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        if connection.requiresKey && (key?.isEmpty ?? true) { throw InsightFailure.missingKey }
        connection.authenticate(&request, key: key)
        let data = try await transport.data(request, connection: connection)
        try Task.checkCancellation()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root[connection.provider == .gemini ? "models" : "data"] as? [[String: Any]] else {
            throw InsightFailure.invalidResponse
        }
        var seen: Set<String> = []
        return entries.prefix(1000).compactMap { entry in
            let id: String
            if connection.provider == .gemini {
                guard let name = entry["name"] as? String,
                      let methods = entry["supportedGenerationMethods"] as? [String], methods.contains("generateContent") else { return nil }
                id = name.hasPrefix("models/") ? String(name.dropFirst(7)) : name
            } else {
                guard let value = entry["id"] as? String else { return nil }
                id = value
            }
            guard !id.isEmpty, id.count <= 200, seen.insert(id).inserted else { return nil }
            let label = entry["displayName"] as? String ?? entry["display_name"] as? String ?? id
            return LLMModel(id: id, name: String(label.prefix(200)))
        }
    }
}
