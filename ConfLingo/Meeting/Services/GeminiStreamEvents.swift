import Foundation

struct GeminiStreamEvents: LLMStreamEvents {
    private(set) var content = ""
    private(set) var ended = false
    private(set) var usage: InsightUsage?

    mutating func consume(_ text: String) throws {
        if text == "[DONE]" {
            guard ended else { throw InsightFailure.invalidResponse }
            return
        }
        let chunk = try JSONDecoder().decode(Chunk.self, from: Data(text.utf8))
        if chunk.promptFeedback?.blockReason != nil { throw InsightFailure.blocked }
        if let metadata = chunk.usageMetadata, let input = metadata.promptTokenCount,
           let output = metadata.candidatesTokenCount, input >= 0, output >= 0, (metadata.thoughtsTokenCount ?? 0) >= 0 {
            usage = InsightUsage(inputTokens: input, outputTokens: output, thinkingTokens: metadata.thoughtsTokenCount ?? 0)
        }
        guard let candidates = chunk.candidates, !candidates.isEmpty else { return }
        guard !ended, candidates.count == 1, let candidate = candidates.first,
              candidate.index == nil || candidate.index == 0 else { throw InsightFailure.invalidResponse }
        for part in candidate.content?.parts ?? [] where part.thought != true {
            content += part.text ?? ""
            guard content.utf8.count <= LLMResponseLimits.payloadBytes else { throw InsightFailure.oversized }
        }
        if let reason = candidate.finishReason {
            guard reason == "STOP" else { throw reason == "MAX_TOKENS" ? InsightFailure.oversized : .blocked }
            ended = true
        }
    }

    private struct Chunk: Decodable {
        let candidates: [Candidate]?
        let usageMetadata: Usage?
        let promptFeedback: Feedback?
    }
    private struct Candidate: Decodable {
        let index: Int?
        let content: Content?
        let finishReason: String?
    }
    private struct Content: Decodable { let parts: [Part]? }
    private struct Part: Decodable { let text: String?; let thought: Bool? }
    private struct Usage: Decodable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
        let thoughtsTokenCount: Int?
    }
    private struct Feedback: Decodable { let blockReason: String? }
}
