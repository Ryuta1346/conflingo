import Foundation

struct GeminiStreamDecoder {
    private var line = Data()
    private var frame: [String] = []
    private var totalBytes = 0
    private var content = ""
    private var ended = false
    private var usage: InsightUsage?

    var previewText: String? {
        guard let prefix = content.range(of: #"^\s*\{\s*"text"\s*:\s*""#, options: .regularExpression) else { return nil }
        var encoded = "\""
        var escaped = false
        for character in content[prefix.upperBound...] {
            if character == "\"", !escaped {
                encoded.append(character)
                return try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
            }
            encoded.append(character)
            escaped = character == "\\" && !escaped
        }
        // Incomplete escape sequences wait for the next chunk.
        return try? JSONDecoder().decode(String.self, from: Data((encoded + "\"").utf8))
    }

    mutating func consume(_ data: Data) throws {
        totalBytes += data.count
        guard totalBytes <= 262_144 else { throw InsightFailure.oversized }
        for byte in data {
            if byte == 10 {
                try acceptLine()
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
                guard line.count <= 65_536 else { throw InsightFailure.oversized }
            }
        }
    }

    mutating func finish() throws -> InsightResult {
        if !line.isEmpty { try acceptLine(); line.removeAll() }
        if !frame.isEmpty { try acceptFrame() }
        guard ended else { throw InsightFailure.invalidResponse }
        let result = try JSONDecoder().decode(Payload.self, from: Data(content.utf8))
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.text.count <= 8_000, result.evidenceIDs.count <= 30, (result.knowledgeIDs?.count ?? 0) <= 5 else { throw InsightFailure.invalidResponse }
        // Invalid UUIDs must make the response fail, never silently disappear.
        let ids = try result.evidenceIDs.map { value in
            guard let id = UUID(uuidString: value) else { throw InsightFailure.invalidResponse }
            return id
        }
        let knowledgeIDs = try (result.knowledgeIDs ?? []).map { value in
            guard let id = UUID(uuidString: value) else { throw InsightFailure.invalidResponse }
            return id
        }
        return InsightResult(kind: result.kind, text: result.text, evidenceIDs: ids, usage: usage, knowledgeIDs: knowledgeIDs)
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
            guard frame.reduce(0, { $0 + $1.utf8.count }) <= 65_536 else { throw InsightFailure.oversized }
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
            guard content.utf8.count <= 65_536 else { throw InsightFailure.oversized }
        }
        if let reason = candidate.finishReason {
            guard reason == "STOP" else { throw reason == "MAX_TOKENS" ? InsightFailure.oversized : .blocked }
            ended = true
        }
    }

    private struct Payload: Decodable {
        let text: String
        let kind: MeetingInsight.Kind
        let evidenceIDs: [String]
        let knowledgeIDs: [String]?
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
