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

    /// カンマ（, ・、）・改行区切りの文字列をトリム・空除去・大文字小文字無視の
    /// 重複排除（先勝ち）をかけて配列化する。
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw
            .split(whereSeparator: { $0 == "," || $0 == "、" || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }
}
