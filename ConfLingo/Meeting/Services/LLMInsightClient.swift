import Foundation

@MainActor
struct LLMInsightClient: InsightClient {
    let connection: LLMConnection
    let key: () async throws -> String?
    var transport: (any InsightHTTPTransport)?
    var diagnostics = LLMDiagnostics()

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        try await diagnostics.capture(provider: connection.provider, operation: LLMDiagnostics.Operation(request.purpose)) {
            try connection.validate()
            try Task.checkCancellation()
            let key = try await key()
            try Task.checkCancellation()
            if connection.requiresKey && (key?.isEmpty ?? true) { throw InsightFailure.missingKey }
            let http = try transport ?? URLSessionInsightTransport(allowedBaseURL: connection.endpoint(""))
            let sent = try LLMInsightRequest.make(request, connection: connection, key: key)
            var decoder = LLMStreamDecoder(provider: connection.provider)
            try await http.stream(sent) { data in
                try Task.checkCancellation()
                try decoder.consume(data)
                if let text = decoder.previewText, !text.isEmpty { update(text) }
            }
            try Task.checkCancellation()
            return try decoder.finish()
        }
    }
}

@MainActor
struct SelectedLLMClient: InsightClient {
    let settings: LLMSettings
    var transport: (any InsightHTTPTransport)?

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        let connection = settings.selected
        let revision = settings.revision
        let store = settings.credentials.store
        let client = LLMInsightClient(connection: connection, key: {
            let value = try await store.read()
            guard settings.revision == revision else { throw CancellationError() }
            return value
        }, transport: transport)
        let result = try await client.generate(request) { text in
            if settings.revision == revision { update(text) }
        }
        guard settings.revision == revision else { throw CancellationError() }
        return result
    }
}
