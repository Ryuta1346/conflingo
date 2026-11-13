import Foundation

struct LLMResearchResponse {
    private var references: [WebReference] = []
    private let fetchedAt = Date()

    static func decode(_ data: Data, provider: LLMProvider, request: InsightRequest) throws -> MeetingInsight {
        guard data.count <= LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["error"] == nil else {
            throw InsightFailure.invalidResponse
        }
        var decoder = Self()
        let text: String
        var suggestions: String?
        switch provider {
        case .gemini:
            (text, suggestions) = try decoder.gemini(root)
        case .openai: text = try decoder.openai(root)
        case .claude: text = try decoder.claude(root)
        default: throw ResearchFailure.unsupported
        }
        guard !decoder.references.isEmpty else { throw ResearchFailure.noSources }
        let (cleaned, speechIDs, documentIDs) = try localCitations(text, request: request)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, cleaned.count <= 8_000 else {
            throw InsightFailure.invalidResponse
        }
        return MeetingInsight(id: request.id, kind: .answerSuggestion, text: cleaned, priority: 1, evidenceIDs: speechIDs,
            knowledgeReferences: request.knowledge.filter { documentIDs.contains($0.id) },
            webReferences: decoder.references, searchSuggestionsHTML: suggestions)
    }

    private mutating func marker(_ url: String?, title: String?) throws -> String {
        guard let url, let parsed = URL(string: url), WebReference.validURL(parsed) else { throw InsightFailure.invalidResponse }
        if let existing = references.first(where: { $0.url == parsed }) { return "[[web:\(existing.id)]]" }
        guard references.count < 20 else { throw InsightFailure.oversized }
        let reference = WebReference(id: UUID(), url: parsed, title: String((title ?? parsed.host ?? "Web").prefix(200)), fetchedAt: fetchedAt)
        references.append(reference)
        return "[[web:\(reference.id)]]"
    }

    private func checkedText(_ value: String?) throws -> String {
        guard let value, value.count <= 8_000, !value.contains("[[web:") else { throw InsightFailure.invalidResponse }
        return value
    }

    private mutating func gemini(_ root: [String: Any]) throws -> (String, String?) {
        guard let candidate = (root["candidates"] as? [[String: Any]])?.first,
              candidate["finishReason"] as? String == "STOP",
              let content = candidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw InsightFailure.invalidResponse }
        let partsText = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }
        guard partsText.count == 1 else { throw InsightFailure.invalidResponse }
        var text = try checkedText(partsText.first)
        guard let metadata = candidate["groundingMetadata"] as? [String: Any],
              let queries = metadata["webSearchQueries"] as? [String], !queries.isEmpty,
              let chunks = metadata["groundingChunks"] as? [[String: Any]],
              let supports = metadata["groundingSupports"] as? [[String: Any]], !supports.isEmpty else { throw ResearchFailure.noSources }
        let html = (metadata["searchEntryPoint"] as? [String: Any])?["renderedContent"] as? String
        guard let html, !html.isEmpty, html.utf8.count <= 65_536 else { throw InsightFailure.invalidResponse }
        var inserts: [(Int, String)] = []
        for support in supports {
            guard let segment = support["segment"] as? [String: Any],
                  let end = segment["endIndex"] as? Int, end >= 0, end <= text.utf8.count,
                  let segmentText = segment["text"] as? String, !segmentText.isEmpty,
                  let indices = support["groundingChunkIndices"] as? [Int] else { throw InsightFailure.invalidResponse }
            let prefix = String(decoding: text.utf8.prefix(end), as: UTF8.self)
            guard prefix.hasSuffix(segmentText) else { throw InsightFailure.invalidResponse }
            var markers = ""
            for index in indices {
                guard chunks.indices.contains(index), let web = chunks[index]["web"] as? [String: Any] else { throw InsightFailure.invalidResponse }
                markers += try marker(web["uri"] as? String, title: web["title"] as? String)
            }
            inserts.append((prefix.utf16.count, markers))
        }
        for (offset, markers) in inserts.sorted(by: { $0.0 > $1.0 }) {
            text = (text as NSString).replacingCharacters(in: NSRange(location: offset, length: 0), with: markers)
        }
        return (text, html)
    }

    private mutating func openai(_ root: [String: Any]) throws -> String {
        guard root["status"] as? String == "completed", let output = root["output"] as? [[String: Any]] else {
            throw InsightFailure.invalidResponse
        }
        guard output.contains(where: { $0["type"] as? String == "web_search_call" && $0["status"] as? String == "completed" }) else {
            throw ResearchFailure.noSources
        }
        var texts: [String] = []
        for message in output where message["type"] as? String == "message" {
            for part in message["content"] as? [[String: Any]] ?? [] {
                guard part["type"] as? String == "output_text" else { throw InsightFailure.invalidResponse }
                var text = try checkedText(part["text"] as? String)
                var inserts: [(Int, String)] = []
                for annotation in part["annotations"] as? [[String: Any]] ?? [] where annotation["type"] as? String == "url_citation" {
                    guard let start = annotation["start_index"] as? Int, let end = annotation["end_index"] as? Int,
                          start >= 0, end >= start, end <= text.unicodeScalars.count else { throw InsightFailure.invalidResponse }
                    let prefix = String(String.UnicodeScalarView(text.unicodeScalars.prefix(end)))
                    inserts.append((prefix.utf16.count, try marker(annotation["url"] as? String, title: annotation["title"] as? String)))
                }
                for (offset, marker) in inserts.sorted(by: { $0.0 > $1.0 }) {
                    text = (text as NSString).replacingCharacters(in: NSRange(location: offset, length: 0), with: marker)
                }
                texts.append(text)
            }
        }
        return texts.joined(separator: "\n\n")
    }

    private mutating func claude(_ root: [String: Any]) throws -> String {
        guard root["stop_reason"] as? String == "end_turn", let content = root["content"] as? [[String: Any]] else {
            throw InsightFailure.invalidResponse
        }
        let searches = Set(content.filter { $0["type"] as? String == "server_tool_use" && $0["name"] as? String == "web_search" }.compactMap { $0["id"] as? String })
        var sourceURLs = Set<String>()
        for block in content where block["type"] as? String == "web_search_tool_result" {
            guard let id = block["tool_use_id"] as? String, searches.contains(id),
                  let results = block["content"] as? [[String: Any]] else { throw InsightFailure.invalidResponse }
            sourceURLs.formUnion(results.filter { $0["type"] as? String == "web_search_result" }.compactMap { $0["url"] as? String })
        }
        guard !sourceURLs.isEmpty else { throw ResearchFailure.noSources }
        var texts: [String] = []
        var needsParagraph = false
        for block in content {
            let type = block["type"] as? String
            guard type == "text" else {
                if type == "server_tool_use" || type == "web_search_tool_result" { needsParagraph = true }
                continue
            }
            var text = try checkedText(block["text"] as? String)
            for citation in block["citations"] as? [[String: Any]] ?? [] where citation["type"] as? String == "web_search_result_location" {
                guard let url = citation["url"] as? String, sourceURLs.contains(url) else { throw InsightFailure.invalidResponse }
                text += try marker(url, title: citation["title"] as? String)
            }
            guard !text.isEmpty else { continue }
            if needsParagraph && !texts.isEmpty { texts.append("\n\n") }
            texts.append(text)
            needsParagraph = false
        }
        // 連続textは引用の文中分割を保持し、検索ツールを挟む文章だけ段落を分ける。
        return texts.joined()
    }

    private static func localCitations(_ text: String, request: InsightRequest) throws -> (String, [UUID], [UUID]) {
        let expression = try NSRegularExpression(pattern: #"\[\[(speech|document):([^\]]+)\]\]"#)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        var speechIDs: [UUID] = []
        var documentIDs: [UUID] = []
        for match in matches.reversed() {
            let raw = text as NSString
            guard let id = UUID(uuidString: raw.substring(with: match.range(at: 2))) else { throw InsightFailure.invalidResponse }
            let label: String
            if raw.substring(with: match.range(at: 1)) == "speech" {
                guard request.events.contains(where: { $0.id == id }) else { throw InsightFailure.invalidResponse }
                if !speechIDs.contains(id) { speechIDs.insert(id, at: 0) }
                label = "〔発話〕"
            } else {
                guard let document = request.knowledge.first(where: { $0.id == id }) else { throw InsightFailure.invalidResponse }
                if !documentIDs.contains(id) { documentIDs.insert(id, at: 0) }
                label = "〔資料：\(document.displayTitle)〕"
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: label)
        }
        return (result, speechIDs, documentIDs)
    }
}
