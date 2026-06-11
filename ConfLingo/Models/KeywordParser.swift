import Foundation

/// 専門用語キーワード欄の入力文字列を contextual strings の配列に変換する。
enum KeywordParser {
    /// Code with Claude Tokyo Extended (2026-06-11) 向けプリセット。
    /// 登壇内容（Claude Code / sub-agents / MCP / Managed Agents / evals 等）の頻出用語。
    static let defaultKeywords = """
    Claude, Claude Code, Anthropic, Opus, Sonnet, Haiku, Fable, \
    MCP, Model Context Protocol, sub-agent, subagents, orchestrator, \
    Managed Agents, Agent SDK, Routines, agentic, multi-agent, \
    evals, evaluation, Constitutional AI, system prompt, prompt engineering, \
    context window, tool use, function calling, hooks, slash command, plugin, skill, \
    RAG, fine-tuning, token, LLM, API key, rate limit, workflow, \
    Bedrock, Vertex AI, primeNumber
    """

    /// 用語1件分。`target` が non-nil なら翻訳後にその訳語へ置換し、
    /// nil なら原文表記のまま保持する（do-not-translate）。
    struct GlossaryEntry: Equatable, Sendable {
        let term: String
        let target: String?
    }

    /// カンマ（, ・、）・改行区切りの各トークンを `term=訳語` 形式としてパースする。
    /// 区切りは最初の `=` / `＝` のみ（訳語側に `=` を含められる）。
    /// `=` なし・訳語が空なら target = nil（従来のキーワード指定と完全互換）。
    /// term の重複は大文字小文字無視で先勝ち排除する。
    static func parseGlossary(_ raw: String) -> [GlossaryEntry] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "、" || $0.isNewline })
            .compactMap { token -> GlossaryEntry? in
                let term: String
                let target: String?
                if let eq = token.firstIndex(where: { $0 == "=" || $0 == "＝" }) {
                    term = String(token[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let rawTarget = String(token[token.index(after: eq)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    target = rawTarget.isEmpty ? nil : rawTarget
                } else {
                    term = token.trimmingCharacters(in: .whitespacesAndNewlines)
                    target = nil
                }
                guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { return nil }
                return GlossaryEntry(term: term, target: target)
            }
    }

    /// contextual strings 用に term のみを配列化する（訳語部分は含めない）。
    static func parse(_ raw: String) -> [String] {
        parseGlossary(raw).map(\.term)
    }
}
