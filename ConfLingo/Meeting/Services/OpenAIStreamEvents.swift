import Foundation

struct OpenAIStreamEvents: LLMStreamEvents {
    private(set) var content = ""
    private(set) var ended = false
    private(set) var usage: InsightUsage?

    mutating func consume(_ text: String) throws {
        guard !ended, text != "[DONE]" else { throw InsightFailure.invalidResponse }
        let object = try LLMStreamDecoder.object(text)
        switch object["type"] as? String {
        case "response.output_text.delta":
            guard let delta = object["delta"] as? String,
                  (object["content_index"] as? Int ?? 0) == 0 else { throw InsightFailure.invalidResponse }
            content += delta
        case "response.refusal.delta", "response.refusal.done": throw InsightFailure.blocked
        case "response.completed":
            guard let response = object["response"] as? [String: Any], response["status"] as? String == "completed" else {
                throw InsightFailure.invalidResponse
            }
            if let tokens = response["usage"] as? [String: Any] { usage = LLMStreamDecoder.usage(tokens, input: "input_tokens", output: "output_tokens") ?? usage }
            ended = true
        case "response.failed", "error": throw InsightFailure.invalidResponse
        case "response.incomplete": throw InsightFailure.oversized
        default: break
        }
    }
}
