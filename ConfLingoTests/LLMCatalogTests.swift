import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMCatalogTests {
    @Test func localCatalogUsesInstalledModelIDsWithoutAuthorization() async throws {
        let http = FakeLLMCatalogHTTP()
        http.response = Data(#"{"data":[{"id":"qwen-installed:8b"},{"id":"another-model"}]}"#.utf8)
        let catalog = LLMModelCatalog(transport: http)
        let models = try await catalog.models(for: .preset(.local), key: nil)
        #expect(models.map(\.id) == ["qwen-installed:8b", "another-model"])
        #expect(http.requests.first?.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func geminiCatalogOnlyShowsTextGenerationModels() async throws {
        let http = FakeLLMCatalogHTTP()
        http.response = Data(#"{"models":[{"name":"models/text-model","displayName":"Text","supportedGenerationMethods":["generateContent"]},{"name":"models/embedding","supportedGenerationMethods":["embedContent"]}]}"#.utf8)
        let models = try await LLMModelCatalog(transport: http).models(for: .preset(.gemini), key: "google-key")
        #expect(models.map(\.id) == ["text-model"])
        #expect(http.requests.first?.value(forHTTPHeaderField: "x-goog-api-key") == "google-key")
    }

    @Test func missingKeyAndInvalidURLNeverReachCatalogTransport() async {
        let http = FakeLLMCatalogHTTP()
        let catalog = LLMModelCatalog(transport: http)
        await #expect(throws: InsightFailure.missingKey) { try await catalog.models(for: .preset(.openai), key: nil) }
        var invalid = LLMConnection.preset(.local)
        invalid.baseURL = "http://remote.example/v1"
        await #expect(throws: InsightFailure.invalidEndpoint) { try await catalog.models(for: invalid, key: nil) }
        #expect(http.requests.isEmpty)
    }
}

@MainActor
final class FakeLLMCatalogHTTP: LLMCatalogTransport {
    var response = Data()
    var requests: [URLRequest] = []
    func data(_ request: URLRequest, connection: LLMConnection) async throws -> Data {
        requests.append(request)
        return response
    }
}
