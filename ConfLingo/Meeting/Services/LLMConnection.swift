import Foundation

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case gemini, openai, claude, kimi, deepseek, custom, local
    var id: Self { self }
    var label: String {
        switch self {
        case .gemini: "Gemini"
        case .openai: "OpenAI"
        case .claude: "Claude"
        case .kimi: "Kimi"
        case .deepseek: "DeepSeek"
        case .custom: "その他クラウド（OpenAI互換）"
        case .local: "ローカルLLM（Qwenなど）"
        }
    }
    var baseURL: String {
        switch self {
        case .gemini: "https://generativelanguage.googleapis.com/v1beta"
        case .openai: "https://api.openai.com/v1"
        case .claude: "https://api.anthropic.com/v1"
        case .kimi: "https://api.moonshot.ai/v1"
        case .deepseek: "https://api.deepseek.com"
        case .custom: ""
        case .local: "http://localhost:11434/v1"
        }
    }
    var isCustomEndpoint: Bool { self == .custom || self == .local }
    var usesChatCompletions: Bool { ![.gemini, .openai, .claude].contains(self) }
}

enum LLMOutputFormat: String, Codable, CaseIterable, Identifiable {
    case schema, json, prompt
    var id: Self { self }
    var label: String {
        switch self {
        case .schema: "JSON Schema"
        case .json: "JSONモード"
        case .prompt: "プロンプトでJSONを指定"
        }
    }
}

struct LLMConnection: Codable, Equatable, Identifiable {
    static let legacyGeminiID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var id: UUID
    var provider: LLMProvider
    var name: String
    var baseURL: String
    var model: String
    var outputFormat: LLMOutputFormat

    static func preset(_ provider: LLMProvider) -> Self {
        Self(id: UUID(), provider: provider, name: provider.label, baseURL: provider.baseURL,
             model: provider == .gemini ? GeminiInsightClient.model : "",
             outputFormat: [.kimi, .deepseek].contains(provider) ? .json : .schema)
    }
    static var legacyGemini: Self {
        var result = preset(.gemini)
        result.id = legacyGeminiID
        return result
    }
    var keychainService: String {
        id == Self.legacyGeminiID ? "com.gavrri.conflingo.gemini-api" : "com.gavrri.conflingo.llm.\(id.uuidString)"
    }
    var destinationLabel: String { "\(name) · \(model.isEmpty ? "モデル未選択" : model)" }
    var requiresKey: Bool { provider != .local }

    func endpoint(_ path: String) throws -> URL {
        guard let parts = URLComponents(string: baseURL),
              let host = parts.host?.lowercased(), !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!),
              parts.scheme == "https" || (provider == .local && parts.scheme == "http"),
              !parts.percentEncodedPath.contains("%"), !parts.path.split(separator: "/").contains(".."),
              let url = parts.url else { throw InsightFailure.invalidEndpoint }
        if provider == .local {
            guard ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host) else { throw InsightFailure.invalidEndpoint }
        }
        if !provider.isCustomEndpoint {
            guard baseURL == provider.baseURL else { throw InsightFailure.invalidEndpoint }
        }
        return url.appendingPathComponent(path)
    }

    func validate() throws {
        _ = try endpoint("models")
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 100,
              !model.isEmpty, model.count <= 200,
              model.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.:/").contains($0) }),
              !model.contains(".."), !model.hasPrefix("/"), !model.hasSuffix("/") else {
            throw InsightFailure.invalidConfiguration
        }
    }
}
