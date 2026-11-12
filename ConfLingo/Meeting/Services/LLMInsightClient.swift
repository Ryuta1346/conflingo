import Foundation

@MainActor
struct LLMInsightClient: InsightClient {
    let connection: LLMConnection
    let key: () async throws -> String?
    var transport: (any InsightHTTPTransport)?

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        try connection.validate()
        try Task.checkCancellation()
        let key = try await key()
        try Task.checkCancellation()
        if connection.requiresKey && (key?.isEmpty ?? true) { throw InsightFailure.missingKey }
        let http = try transport ?? URLSessionInsightTransport(allowedBaseURL: connection.endpoint(""))
        if connection.provider == .gemini {
            return try await GeminiInsightClient(key: { key }, transport: http, modelID: connection.model).generate(request, update: update)
        }
        let sent = try makeRequest(request, key: key)
        var decoder = LLMStreamDecoder(provider: connection.provider)
        try await http.stream(sent) { data in
            try Task.checkCancellation()
            try decoder.consume(data)
            if let text = decoder.previewText, !text.isEmpty { update(text) }
        }
        try Task.checkCancellation()
        return try decoder.finish()
    }

    private func makeRequest(_ request: InsightRequest, key: String?) throws -> URLRequest {
        let prompt = try InsightPrompt(request)
        let schema = prompt.jsonSchema
        let schemaText = String(decoding: try JSONSerialization.data(withJSONObject: schema), as: UTF8.self)
        let instruction = prompt.instruction + "\nReturn only a JSON object matching this JSON schema (no markdown):\n" + schemaText
        let user = prompt.context + "\n" + prompt.question
        var body: [String: Any] = ["model": connection.model, "stream": true]
        let path: String
        switch connection.provider {
        case .openai:
            path = "responses"
            body["store"] = false
            body["max_output_tokens"] = 8192
            body["instructions"] = instruction
            body["input"] = [["role": "user", "content": user]]
            body["text"] = ["format": ["type": "json_schema", "name": "meeting_insight", "strict": true, "schema": schema]]
        case .claude:
            path = "messages"
            body["max_tokens"] = 8192
            body["system"] = instruction
            body["messages"] = [["role": "user", "content": user]]
            body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
        default:
            path = "chat/completions"
            body["max_tokens"] = 8192
            body["messages"] = [["role": "system", "content": instruction], ["role": "user", "content": user]]
            switch connection.outputFormat {
            case .schema: body["response_format"] = ["type": "json_schema", "json_schema": ["name": "meeting_insight", "strict": true, "schema": schema]]
            case .json: body["response_format"] = ["type": "json_object"]
            case .prompt: break
            }
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard data.count <= 131_072 else { throw InsightFailure.oversized }
        var result = URLRequest(url: try connection.endpoint(path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeoutSeconds)
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("text/event-stream", forHTTPHeaderField: "Accept")
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
