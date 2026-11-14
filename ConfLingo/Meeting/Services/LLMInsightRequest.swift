import Foundation

@MainActor
enum LLMInsightRequest {
    static func make(_ request: InsightRequest, connection: LLMConnection, key: String?) throws -> URLRequest {
        if connection.provider == .gemini {
            return try gemini(request, connection: connection, key: key)
        }
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
        return try LLMHTTPRequest.make(connection: connection, path: path, body: body, key: key,
                                       timeout: request.timeoutSeconds, streaming: true)
    }

    private static func gemini(_ request: InsightRequest, connection: LLMConnection, key: String?) throws -> URLRequest {
        let prompt = try InsightPrompt(request)
        var generation: [String: Any] = ["maxOutputTokens": 8192, "responseMimeType": "application/json",
                                          "responseSchema": prompt.geminiSchema]
        if connection.model == GeminiInsightClient.model { generation["thinkingConfig"] = ["thinkingLevel": "medium"] }
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": prompt.instruction]]],
            "contents": [["role": "user", "parts": [["text": prompt.context],
                                                   ["text": prompt.question]]]],
            "generationConfig": generation
        ]
        return try LLMHTTPRequest.make(connection: connection, path: "models/\(connection.model):streamGenerateContent",
                                       body: body, key: key, timeout: request.timeoutSeconds, streaming: true,
                                       queryItems: [URLQueryItem(name: "alt", value: "sse")])
    }
}
