import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMDiagnosticsTests {
    @Test(arguments: LLMProvider.allCases, [401, 429])
    func HTTPFailureIsRecordedOnceAndRethrown(provider: LLMProvider, status: Int) async throws {
        let http = FakeInsightHTTP()
        http.failure = InsightFailure.http(status)
        var events: [LLMDiagnostics.Event] = []
        let client = LLMInsightClient(connection: connection(provider), key: { "synthetic-secret-key" }, transport: http,
            diagnostics: LLMDiagnostics { events.append($0) })
        await #expect(throws: InsightFailure.http(status)) {
            try await client.generate(request()) { _ in }
        }
        #expect(http.requests.count == 1)
        #expect(events == [.init(provider: provider, operation: .assistance, reason: .http, code: status)])
    }

    @Test func missingKeyAndSecretBearingUnknownErrorsNeverLogArbitraryText() async throws {
        var events: [LLMDiagnostics.Event] = []
        let diagnostics = LLMDiagnostics { events.append($0) }
        let http = FakeInsightHTTP()
        let missing = LLMInsightClient(connection: connection(.custom), key: { nil }, transport: http, diagnostics: diagnostics)
        await #expect(throws: InsightFailure.missingKey) { try await missing.generate(request()) { _ in } }
        let secret = NSError(domain: "SECRET-domain", code: 123,
            userInfo: [NSLocalizedDescriptionKey: "SECRET-answer-key-path", NSURLErrorKey: "https://SECRET.example"])
        let unknown = LLMInsightClient(connection: connection(.custom), key: { throw secret }, transport: http, diagnostics: diagnostics)
        do {
            _ = try await unknown.generate(request()) { _ in }
            Issue.record("Expected the original error")
        } catch { #expect(error as NSError === secret) }
        #expect(http.requests.isEmpty)
        #expect(events == [.init(provider: .custom, operation: .assistance, reason: .missingKey, code: nil),
                           .init(provider: .custom, operation: .assistance, reason: .unknown, code: nil)])
        #expect(events.allSatisfy { !$0.message.contains("SECRET") && !$0.message.contains("synthetic") })
    }

    @Test func networkAndCancellationKeepOnlyNumericCodes() async throws {
        let failures: [(any Error, LLMDiagnostics.Reason, Int?)] = [
            (URLError(.timedOut), .timeout, URLError.timedOut.rawValue),
            (URLError(.notConnectedToInternet), .offline, URLError.notConnectedToInternet.rawValue),
            (URLError(.cancelled), .cancelled, URLError.cancelled.rawValue),
            (CancellationError(), .cancelled, nil), (InsightFailure.oversized, .oversized, nil),
            (InsightFailure.invalidResponse, .invalidResponse, nil), (InsightFailure.keyStorage, .keyStorage, nil)
        ]
        for (error, reason, code) in failures {
            var events: [LLMDiagnostics.Event] = []
            let http = FakeInsightHTTP()
            http.failure = error
            let client = LLMInsightClient(connection: connection(.openai), key: { "key" }, transport: http,
                diagnostics: LLMDiagnostics { events.append($0) })
            do { _ = try await client.generate(request()) { _ in }; Issue.record("Expected failure") } catch {}
            #expect(events == [.init(provider: .openai, operation: .assistance, reason: reason, code: code)])
        }
    }

    @Test func operationKindsAndSuccessfulResponses() async throws {
        let purposes: [(InsightRequest.Purpose, LLMDiagnostics.Operation)] = [
            (.assistance, .assistance), (.summary, .summary), (.documentQuestion, .documentQuestion),
            (.transcriptCorrection, .transcriptCorrection), (.webResearch, .webResearch)
        ]
        for (purpose, operation) in purposes {
            var events: [LLMDiagnostics.Event] = []
            let http = FakeInsightHTTP()
            http.chunks = [try responseStream(.openai, payload: responsePayload("answer"))]
            let client = LLMInsightClient(connection: connection(.openai), key: { "key" }, transport: http,
                diagnostics: LLMDiagnostics { events.append($0) })
            let request = try request(purpose)
            #expect(try await client.generate(request) { _ in }.text == "answer")
            #expect(events.isEmpty)
            http.chunks = [Data("data: invalid JSON\n\n".utf8)]
            do { _ = try await client.generate(request) { _ in }; Issue.record("Expected decode failure") } catch {}
            #expect(events.count == 1)
            #expect(events.first?.operation == operation)
        }
    }

    @Test func webAndCatalogFailuresUseTheirOwnOperationAndPreserveError() async throws {
        var events: [LLMDiagnostics.Event] = []
        let diagnostics = LLMDiagnostics { events.append($0) }
        let research = LLMWebResearchClient(connection: connection(.local), key: { nil }, diagnostics: diagnostics)
        await #expect(throws: ResearchFailure.unsupported) { try await research.generate(request(.webResearch)) }
        let catalog = LLMModelCatalog(transport: FakeLLMCatalogHTTP(), diagnostics: diagnostics)
        await #expect(throws: InsightFailure.missingKey) { try await catalog.models(for: connection(.openai), key: nil) }
        #expect(events == [.init(provider: .local, operation: .webResearch, reason: .unsupported, code: nil),
                           .init(provider: .openai, operation: .models, reason: .missingKey, code: nil)])
    }

    @Test func webAndCatalogSuccessDoNotEmitAndNoSourcesIsDistinct() async throws {
        var events: [LLMDiagnostics.Event] = []
        let diagnostics = LLMDiagnostics { events.append($0) }
        let http = DiagnosticResearchHTTP(response: try nativeResearchFixture(.openai))
        let research = LLMWebResearchClient(connection: connection(.openai), key: { "synthetic-key" }, transport: http, diagnostics: diagnostics)
        _ = try await research.generate(request(.webResearch))
        let catalogHTTP = FakeLLMCatalogHTTP()
        catalogHTTP.response = Data(#"{"data":[{"id":"test-model"}]}"#.utf8)
        _ = try await LLMModelCatalog(transport: catalogHTTP, diagnostics: diagnostics).models(for: connection(.local), key: nil)
        #expect(events.isEmpty)
        http.failure = ResearchFailure.noSources
        await #expect(throws: ResearchFailure.noSources) { try await research.generate(request(.webResearch)) }
        #expect(events == [.init(provider: .openai, operation: .webResearch, reason: .noSources, code: nil)])
    }

    private func request(_ purpose: InsightRequest.Purpose = .assistance) throws -> InsightRequest {
        try InsightRequest(sessionID: UUID(), question: "SECRET-question", trigger: .manual, events: [], purpose: purpose)
    }

    private func connection(_ provider: LLMProvider) -> LLMConnection {
        var result = LLMConnection.preset(provider)
        result.model = "SECRET-model"
        result.name = "SECRET-connection"
        if provider == .custom { result.baseURL = "https://SECRET.example/private" }
        return result
    }
}

@MainActor
private final class DiagnosticResearchHTTP: ResearchHTTPTransport {
    let response: Data
    var failure: (any Error)?
    init(response: Data) { self.response = response }
    func fetch(_ request: URLRequest) async throws -> Data {
        if let failure { throw failure }
        return response
    }
}
