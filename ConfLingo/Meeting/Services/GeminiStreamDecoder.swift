import Foundation

struct GeminiStreamDecoder {
    private var line = Data()
    private var frame: [String] = []
    private var totalBytes = 0
    private var content = ""
    private var ended = false
    private var usage: InsightUsage?

    var previewText: String? { InsightPayload.preview(content) }

    mutating func consume(_ data: Data) throws {
        totalBytes += data.count
        guard totalBytes <= LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
        for byte in data {
            if byte == 10 {
                try acceptLine()
                line.removeAll(keepingCapacity: true)
            } else {
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
            frame.append(value)
            guard frame.reduce(0, { $0 + $1.utf8.count }) <= LLMResponseLimits.eventBytes else { throw InsightFailure.oversized }
        }
    }

    private mutating func acceptFrame() throws {
        let text = frame.joined(separator: "\n")
        frame.removeAll(keepingCapacity: true)
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
