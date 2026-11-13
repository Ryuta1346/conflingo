import Foundation

struct LLMStreamDecoder {
    let provider: LLMProvider
    private var line = Data()
    private var frame: [String] = []
    private var frameBytes = 0
    private var totalBytes = 0
    private var content = ""
    private var finished = false
    private var ended = false
    private var usage: InsightUsage?
    private var anthropicInput: Int?

    init(provider: LLMProvider) { self.provider = provider }

    var previewText: String? { InsightPayload.preview(content) }

    mutating func consume(_ data: Data) throws {
        totalBytes += data.count
        guard totalBytes <= LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
        for byte in data {
            if byte == 10 { try acceptLine(); line.removeAll(keepingCapacity: true) }
            else {
                line.append(byte)
                guard line.count <= LLMResponseLimits.eventBytes else { throw InsightFailure.oversized }
            }
        }
    }

    mutating func finish() throws -> InsightResult {
        if !line.isEmpty { try acceptLine(); line.removeAll() }
        if !frame.isEmpty { try acceptFrame() }
        guard ended else { throw InsightFailure.invalidResponse }
        return try InsightPayload.decode(content, usage: usage)
    }

    private mutating func acceptLine() throws {
        guard var text = String(data: line, encoding: .utf8) else { throw InsightFailure.invalidResponse }
        if text.last == "\r" { text.removeLast() }
        if text.isEmpty {
            if !frame.isEmpty { try acceptFrame() }
        } else if text.hasPrefix("data:") {
            var value = String(text.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            frameBytes += value.utf8.count
            guard frameBytes <= LLMResponseLimits.eventBytes else { throw InsightFailure.oversized }
            frame.append(value)
        }
    }

    private mutating func acceptFrame() throws {
        let text = frame.joined(separator: "\n")
        frame.removeAll(keepingCapacity: true)
        frameBytes = 0
        guard !ended else { throw InsightFailure.invalidResponse }
        if text == "[DONE]" {
            guard provider.usesChatCompletions, finished else { throw InsightFailure.invalidResponse }
            ended = true
            return
        }
        guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
            throw InsightFailure.invalidResponse
        }
        if object["error"] != nil { throw InsightFailure.invalidResponse }
        if provider == .openai { try acceptResponses(object) }
        else if provider == .claude { try acceptAnthropic(object) }
        else { try acceptChat(object) }
        guard content.utf8.count <= LLMResponseLimits.payloadBytes else { throw InsightFailure.oversized }
    }

    private mutating func acceptResponses(_ object: [String: Any]) throws {
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
            if let tokens = response["usage"] as? [String: Any] { readUsage(tokens, input: "input_tokens", output: "output_tokens") }
            ended = true
        case "response.failed", "error": throw InsightFailure.invalidResponse
        case "response.incomplete": throw InsightFailure.oversized
        default: break
        }
    }

    private mutating func acceptAnthropic(_ object: [String: Any]) throws {
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

    private mutating func acceptChat(_ object: [String: Any]) throws {
        if let tokens = object["usage"] as? [String: Any] { readUsage(tokens, input: "prompt_tokens", output: "completion_tokens") }
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

    private mutating func readUsage(_ tokens: [String: Any], input: String, output: String) {
        guard let inputCount = tokens[input] as? Int, let outputCount = tokens[output] as? Int,
              inputCount >= 0, outputCount >= 0 else { return }
        let details = tokens["output_tokens_details"] as? [String: Any] ?? tokens["completion_tokens_details"] as? [String: Any]
        let thinking = details?["reasoning_tokens"] as? Int ?? 0
        guard thinking >= 0, thinking <= outputCount else { return }
        usage = InsightUsage(inputTokens: inputCount, outputTokens: outputCount - thinking, thinkingTokens: thinking)
    }
}
