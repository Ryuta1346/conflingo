import Foundation

struct ChatStreamEvents: LLMStreamEvents {
    private(set) var content = ""
    private(set) var ended = false
    private(set) var usage: InsightUsage?
    private var finished = false

    mutating func consume(_ text: String) throws {
        guard !ended else { throw InsightFailure.invalidResponse }
        if text == "[DONE]" {
            guard finished else { throw InsightFailure.invalidResponse }
            ended = true
            return
        }
        let object = try LLMStreamDecoder.object(text)
        if let tokens = object["usage"] as? [String: Any] { usage = LLMStreamDecoder.usage(tokens, input: "prompt_tokens", output: "completion_tokens") ?? usage }
        guard let choices = object["choices"] as? [[String: Any]] else { throw InsightFailure.invalidResponse }
        if choices.isEmpty { return }
        guard !finished, choices.count == 1, let choice = choices.first,
              choice["index"] as? Int == 0 else { throw InsightFailure.invalidResponse }
        if let delta = choice["delta"] as? [String: Any] {
            if let refusal = delta["refusal"] as? String, !refusal.isEmpty { throw InsightFailure.blocked }
            if delta["tool_calls"] != nil { throw InsightFailure.invalidResponse }
            if let text = delta["content"] as? String { content += text }
        }
        if let reason = choice["finish_reason"] as? String {
            guard reason == "stop" else { throw reason == "length" ? InsightFailure.oversized : .blocked }
            finished = true
        }
    }
}
