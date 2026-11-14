import Foundation

protocol LLMStreamEvents {
    var content: String { get }
    var usage: InsightUsage? { get }
    var ended: Bool { get }
    mutating func consume(_ text: String) throws
}

struct LLMStreamDecoder {
    private var framer = SSEFramer()
    private var events: any LLMStreamEvents

    init(provider: LLMProvider) {
        switch provider {
        case .gemini: events = GeminiStreamEvents()
        case .openai: events = OpenAIStreamEvents()
        case .claude: events = ClaudeStreamEvents()
        case .kimi, .deepseek, .custom, .local: events = ChatStreamEvents()
        }
    }

    var previewText: String? { InsightPayload.preview(events.content) }

    mutating func consume(_ data: Data) throws {
        for byte in data {
            if let text = try framer.consume(byte) { try accept(text) }
        }
    }

    mutating func finish() throws -> InsightResult {
        if let text = try framer.finish() { try accept(text) }
        guard events.ended else { throw InsightFailure.invalidResponse }
        return try InsightPayload.decode(events.content, usage: events.usage)
    }

    private mutating func accept(_ text: String) throws {
        try events.consume(text)
        guard events.content.utf8.count <= LLMResponseLimits.payloadBytes else { throw InsightFailure.oversized }
    }

    static func object(_ text: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              object["error"] == nil else { throw InsightFailure.invalidResponse }
        return object
    }

    static func usage(_ tokens: [String: Any], input: String, output: String) -> InsightUsage? {
        guard let inputCount = tokens[input] as? Int, let outputCount = tokens[output] as? Int,
              inputCount >= 0, outputCount >= 0 else { return nil }
        let details = tokens["output_tokens_details"] as? [String: Any] ?? tokens["completion_tokens_details"] as? [String: Any]
        let thinking = details?["reasoning_tokens"] as? Int ?? 0
        guard thinking >= 0, thinking <= outputCount else { return nil }
        return InsightUsage(inputTokens: inputCount, outputTokens: outputCount - thinking, thinkingTokens: thinking)
    }
}
