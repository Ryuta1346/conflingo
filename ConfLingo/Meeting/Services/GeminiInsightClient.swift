import Foundation

@MainActor
struct GeminiInsightClient: InsightClient {
    nonisolated static let model = "gemini-3.8-flash"
    let key: () async throws -> String?
    var transport: any InsightHTTPTransport = URLSessionInsightTransport()
    var modelID = Self.model

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        var connection = LLMConnection.preset(.gemini)
        connection.model = modelID
        return try await LLMInsightClient(connection: connection, key: key, transport: transport).generate(request, update: update)
    }
}
