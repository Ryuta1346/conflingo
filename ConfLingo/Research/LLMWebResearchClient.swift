import Foundation

@MainActor
protocol LLMWebResearching {
    func generate(_ request: InsightRequest) async throws -> MeetingInsight
}

extension LLMProvider {
    var supportsWebResearch: Bool { [.gemini, .openai, .claude].contains(self) }
}

enum ResearchFailure: Error, Equatable, LocalizedError {
    case unsupported, noSources
    var errorDescription: String? {
        switch self {
        case .unsupported: "この接続のWeb検索には未対応です。Gemini・OpenAI・ClaudeのWeb検索対応モデルを選んでください。資料・発話への通常の質問は利用できます。"
        case .noSources: "Web検索の実行と出典を確認できませんでした。調査済みの回答としては保存しません。モデルのWeb検索対応や利用権限を確認してください。"
        }
    }
}

@MainActor
protocol ResearchHTTPTransport {
    func fetch(_ request: URLRequest) async throws -> Data
}

@MainActor
struct URLSessionResearchTransport: ResearchHTTPTransport {
    let allowedBaseURL: URL
    var configuration: URLSessionConfiguration = .ephemeral

    func fetch(_ request: URLRequest) async throws -> Data {
        guard let url = request.url, URLSessionInsightTransport.permits(url, base: allowedBaseURL) else {
            throw InsightFailure.invalidEndpoint
        }
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw InsightFailure.invalidResponse }
        guard response.statusCode == 200 else { throw InsightFailure.http(response.statusCode) }
        guard response.mimeType == "application/json" else { throw InsightFailure.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < LLMResponseLimits.wireBytes else { throw InsightFailure.oversized }
            data.append(byte)
        }
        return data
    }
}

@MainActor
struct LLMWebResearchClient: LLMWebResearching {
    let connection: LLMConnection
    let key: () async throws -> String?
    var transport: (any ResearchHTTPTransport)?
    var diagnostics = LLMDiagnostics()

    func generate(_ request: InsightRequest) async throws -> MeetingInsight {
        try await diagnostics.capture(provider: connection.provider, operation: .webResearch) {
            guard connection.provider.supportsWebResearch else { throw ResearchFailure.unsupported }
            try connection.validate()
            try Task.checkCancellation()
            let token = try await key()
            try Task.checkCancellation()
            guard let token, APIKeyCredentials.isValid(token) else { throw InsightFailure.missingKey }
            let sent = try LLMResearchRequest.make(request, connection: connection, key: token)
            let transport = try transport ?? URLSessionResearchTransport(allowedBaseURL: connection.endpoint(""))
            let data = try await transport.fetch(sent)
            try Task.checkCancellation()
            return try LLMResearchResponse.decode(data, provider: connection.provider, request: request)
        }
    }
}

@MainActor
struct SelectedLLMResearchClient: LLMWebResearching {
    let settings: LLMSettings
    var transport: (any ResearchHTTPTransport)?
    func generate(_ request: InsightRequest) async throws -> MeetingInsight {
        let connection = settings.selected
        let revision = settings.revision
        let credentials = settings.credentials.store
        let result = try await LLMWebResearchClient(connection: connection, key: {
            let value = try await credentials.read()
            guard settings.revision == revision else { throw CancellationError() }
            return value
        }, transport: transport).generate(request)
        guard settings.revision == revision else { throw CancellationError() }
        return result
    }
}
