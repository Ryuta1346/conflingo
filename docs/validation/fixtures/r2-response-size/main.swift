import Foundation

// Only the app's surrounding model types are substituted. The three response
// decoders, InsightPayload, and WebReference are compiled from production sources.
enum InsightFailure: Error { case oversized, invalidResponse, blocked }
enum ResearchFailure: Error { case unsupported, noSources }
enum LLMProvider: String, CaseIterable {
    case gemini, openai, claude, kimi, deepseek, custom, local
    var usesChatCompletions: Bool { ![.gemini, .openai, .claude].contains(self) }
}
struct InsightUsage { let inputTokens: Int; let outputTokens: Int; let thinkingTokens: Int }
struct InsightResult {
    let kind: MeetingInsight.Kind; let text: String; let evidenceIDs: [UUID]
    let usage: InsightUsage?; let knowledgeIDs: [UUID]; let supplement: String?
}
struct Event { let id: UUID }
struct Knowledge { let id: UUID; let displayTitle: String }
struct InsightRequest { let id = UUID(); let events: [Event] = []; let knowledge: [Knowledge] = [] }
struct MeetingInsight {
    enum Kind: String, Decodable { case answerSuggestion }
    let id: UUID; let kind: Kind; let text: String; let priority: Int; let evidenceIDs: [UUID]
    let knowledgeReferences: [Knowledge]; let webReferences: [WebReference]; let searchSuggestionsHTML: String?
}

func frame(_ value: [String: Any]) throws -> Data {
    Data("data: ".utf8) + (try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)) + Data("\n\n".utf8)
}
func stream(_ provider: LLMProvider, payload: String, split: Bool) throws -> Data {
    let parts = split ? payload.map(String.init) : [payload]
    var result = Data()
    for part in parts {
        switch provider {
        case .gemini: result += try frame(["candidates": [["index": 0, "content": ["parts": [["text": part]]]]]])
        case .openai: result += try frame(["type": "response.output_text.delta", "delta": part])
        case .claude: result += try frame(["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": part]])
        default: result += try frame(["choices": [["index": 0, "delta": ["content": part], "finish_reason": NSNull()]]])
        }
    }
    switch provider {
    case .gemini: result += try frame(["candidates": [["index": 0, "finishReason": "STOP"]]])
    case .openai: result += try frame(["type": "response.completed", "response": ["status": "completed"]])
    case .claude:
        result += try frame(["type": "message_delta", "delta": ["stop_reason": "end_turn"]])
        result += try frame(["type": "message_stop"])
    default:
        result += try frame(["choices": [["index": 0, "delta": [:], "finish_reason": "stop"]]])
        result += Data("data: [DONE]\n\n".utf8)
    }
    return result
}
func probeStream(_ provider: LLMProvider, payload: String, split: Bool) throws -> [String: Any] {
    let bytes = try stream(provider, payload: payload, split: split)
    var status = "success"
    var textCount = 0
    do {
        if provider == .gemini {
            var decoder = GeminiStreamDecoder()
            for offset in stride(from: 0, to: bytes.count, by: 1024) {
                try decoder.consume(bytes.subdata(in: offset..<min(offset + 1024, bytes.count)))
            }
            textCount = try decoder.finish().text.count
        } else {
            var decoder = LLMStreamDecoder(provider: provider)
            for offset in stride(from: 0, to: bytes.count, by: 1024) {
                try decoder.consume(bytes.subdata(in: offset..<min(offset + 1024, bytes.count)))
            }
            textCount = try decoder.finish().text.count
        }
    } catch { status = String(describing: error) }
    return ["provider": provider.rawValue, "split": split, "wireBytes": bytes.count,
            "payloadBytes": payload.utf8.count, "decodedCharacters": textCount, "status": status]
}
func nativeResearchFixture(_ provider: LLMProvider, cited: Bool = true, text: String = "Finding", url: String = "https://example.com/source") throws -> Data {
    let value: [String: Any]
    switch provider {
    case .gemini:
        value = ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": text]]], "groundingMetadata": [
            "webSearchQueries": ["topic"], "searchEntryPoint": ["renderedContent": "<div>Google search suggestions</div>"],
            "groundingChunks": [["web": ["uri": url, "title": "Source"]]],
            "groundingSupports": cited ? [["segment": ["startIndex": 0, "endIndex": text.utf8.count, "text": text], "groundingChunkIndices": [0]]] : []
        ]]]]
    case .openai:
        value = ["status": "completed", "output": [
            ["type": "web_search_call", "status": "completed"],
            ["type": "message", "content": [["type": "output_text", "text": text, "annotations": cited ? [
                ["type": "url_citation", "start_index": 0, "end_index": text.unicodeScalars.count, "url": url, "title": "Source"]
            ] : []]]]
        ]]
    default:
        value = ["stop_reason": "end_turn", "content": [
            ["type": "server_tool_use", "name": "web_search", "id": "search1"],
            ["type": "web_search_tool_result", "tool_use_id": "search1", "content": [["type": "web_search_result", "url": url, "title": "Source"]]],
            ["type": "text", "text": text, "citations": cited ? [["type": "web_search_result_location", "url": url, "title": "Source", "cited_text": "source excerpt"]] : []]
        ]]
    }
    return try JSONSerialization.data(withJSONObject: value)
}

var rows: [[String: Any]] = []
for language in ["en", "ja"] {
    let text = String(repeating: language == "en" ? "a" : "あ", count: 8000)
    let payload = String(decoding: try JSONSerialization.data(withJSONObject: ["text": text, "kind": "answerSuggestion", "evidenceIDs": []], options: .sortedKeys), as: UTF8.self)
    for provider in LLMProvider.allCases {
        for split in [false, true] {
            var row = try probeStream(provider, payload: payload, split: split)
            row["language"] = language
            row["kind"] = "SSE"
            rows.append(row)
            precondition(row["status"] as? String == "success")
        }
    }
}
for provider in [LLMProvider.gemini, .openai, .claude] {
    for padded in [false, true] {
        var data = try nativeResearchFixture(provider)
        // JSON whitespace changes wire size without changing any parsed field.
        if padded { data.append(Data(repeating: 32, count: 262_145 - data.count)) }
        var status = "success"
        do { _ = try LLMResearchResponse.decode(data, provider: provider, request: InsightRequest()) }
        catch { status = String(describing: error) }
        rows.append(["provider": provider.rawValue, "kind": "researchJSON", "padded": padded,
                     "wireBytes": data.count, "textCharacters": 7, "status": status])
        precondition(status == "success")
    }
}
let output = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: output, as: UTF8.self))
