import Foundation

enum LLMProvider { case gemini, openai, claude, local; var usesChatCompletions: Bool { self == .local } }
enum InsightFailure: Error { case invalidResponse, oversized, blocked }
struct InsightUsage { let inputTokens: Int; let outputTokens: Int; let thinkingTokens: Int }
struct InsightResult { let text: String }
enum InsightPayload {
    static func preview(_ text: String) -> String? { text }
    static func decode(_ text: String, usage: InsightUsage?) throws -> InsightResult { InsightResult(text: text) }
}
let payload = "{\"text\":\"answer\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}"
let delta = String(decoding: try JSONSerialization.data(withJSONObject: ["type":"response.output_text.delta", "delta":payload]), as: UTF8.self)
let blanks = String(repeating: "data:\n", count: 70_000)
let first = "data: {\n" + blanks + "data: " + delta.dropFirst() + "\n\n"
let end = "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
let stream = Data((first + end).utf8)
var decoder = LLMStreamDecoder(provider: .openai)
let started = Date()
do { try decoder.consume(stream); print("accepted wire=\(stream.count), decoded frame approximately=\(70000+delta.utf8.count), limit=\(LLMResponseLimits.eventBytes), result=\(try decoder.finish().text), seconds=\(Date().timeIntervalSince(started))") }
catch { print("rejected: \(error)") }
