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
        guard let start = textValueStart(in: content) else { return nil }
        var encoded = "\""
        var escaped = false
        for character in content.unicodeScalars[start...] {
            if character == "\"", !escaped {
                encoded.unicodeScalars.append(character)
                return try? JSONDecoder().decode(String.self, from: Data(encoded.utf8))
            }
            encoded.unicodeScalars.append(character)
            escaped = character == "\\" && !escaped
        }
        // Incomplete escape sequences wait for the next chunk.
        return try? JSONDecoder().decode(String.self, from: Data((encoded + "\"").utf8))
    }

    private static func textValueStart(in content: String) -> String.Index? {
        let scalars = content.unicodeScalars
        guard scalars.first(where: { !$0.properties.isWhitespace }) == "{" else { return nil }
        var depth = 0
        var stringStart: String.Index?
        var escaped = false
        for index in scalars.indices {
            let character = scalars[index]
            if let start = stringStart {
                if character == "\"", !escaped {
                    stringStart = nil
                    guard depth == 1,
                          (try? JSONDecoder().decode(String.self, from: Data(content[start...index].utf8))) == "text" else { continue }
                    var remainder = scalars[scalars.index(after: index)...].drop(while: { $0.properties.isWhitespace })
                    guard remainder.first == ":" else { continue }
                    remainder = remainder.dropFirst().drop(while: { $0.properties.isWhitespace })
                    guard remainder.first == "\"" else { return nil }
                    return scalars.index(after: remainder.startIndex)
                }
                escaped = character == "\\" && !escaped
            } else if character == "\"" {
                stringStart = index
                escaped = false
            } else if character == "{" || character == "[" {
                depth += 1
            } else if character == "}" || character == "]" {
                depth -= 1
                if depth == 0 { return nil }
            }
        }
        return nil
    }
}
