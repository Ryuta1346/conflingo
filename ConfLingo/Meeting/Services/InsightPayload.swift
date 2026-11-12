import Foundation

struct InsightPayload: Decodable {
    let text: String
    let kind: MeetingInsight.Kind
    let evidenceIDs: [String]
    let knowledgeIDs: [String]?
    let supplement: String?

    static func decode(_ content: String, usage: InsightUsage?) throws -> InsightResult {
        let result = try JSONDecoder().decode(Self.self, from: Data(content.utf8))
        guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.text.count <= 8_000, result.evidenceIDs.count <= 30, (result.knowledgeIDs?.count ?? 0) <= 5,
              (result.supplement?.count ?? 0) <= 8_000 else { throw InsightFailure.invalidResponse }
        // Invalid UUIDs must make the response fail, never silently disappear.
        let ids = try result.evidenceIDs.map { value in
            guard let id = UUID(uuidString: value) else { throw InsightFailure.invalidResponse }
            return id
        }
        let knowledgeIDs = try (result.knowledgeIDs ?? []).map { value in
            guard let id = UUID(uuidString: value) else { throw InsightFailure.invalidResponse }
            return id
        }
        return InsightResult(kind: result.kind, text: result.text, evidenceIDs: ids, usage: usage, knowledgeIDs: knowledgeIDs, supplement: result.supplement)
    }
    static func preview(_ content: String) -> String? {
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
}
