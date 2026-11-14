import Foundation

struct ClaudeStreamEvents: LLMStreamEvents {
    private(set) var content = ""
    private(set) var ended = false
    private(set) var usage: InsightUsage?
    private var finished = false
    private var anthropicInput: Int?

    mutating func consume(_ text: String) throws {
        guard !ended, text != "[DONE]" else { throw InsightFailure.invalidResponse }
        let object = try LLMStreamDecoder.object(text)
        switch object["type"] as? String {
        case "message_start":
            let message = object["message"] as? [String: Any]
            let tokens = message?["usage"] as? [String: Any]
            if let input = tokens?["input_tokens"] as? Int {
                anthropicInput = input + (tokens?["cache_creation_input_tokens"] as? Int ?? 0) + (tokens?["cache_read_input_tokens"] as? Int ?? 0)
            }
        case "content_block_delta":
            guard !finished else { throw InsightFailure.invalidResponse }
            if let delta = object["delta"] as? [String: Any], delta["type"] as? String == "text_delta",
               let text = delta["text"] as? String { content += text }
        case "message_delta":
            let delta = object["delta"] as? [String: Any]
            if let reason = delta?["stop_reason"] as? String {
                guard reason == "end_turn" else { throw reason == "max_tokens" ? InsightFailure.oversized : .blocked }
                finished = true
            }
            if let tokens = object["usage"] as? [String: Any], let output = tokens["output_tokens"] as? Int,
               let input = anthropicInput, input >= 0, output >= 0 {
                usage = InsightUsage(inputTokens: input, outputTokens: output, thinkingTokens: 0)
            }
        case "message_stop":
            guard finished else { throw InsightFailure.invalidResponse }
            ended = true
        case "error": throw InsightFailure.invalidResponse
        default: break
        }
    }
}
