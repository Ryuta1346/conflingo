import Foundation
import Synchronization
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct ResearchTransportTests {
    @Test(arguments: [401, 403, 429, 500, 302])
    func errorsAreTypedAndNotRetried(status: Int) async throws {
        WebProtocol.response.withLock { $0 = .init(status: status, mime: "application/json", data: Data("private error".utf8)) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebProtocol.self]
        let transport = URLSessionResearchTransport(allowedBaseURL: try #require(URL(string: LLMProvider.openai.baseURL)), configuration: config)
        let request = URLRequest(url: try #require(URL(string: LLMProvider.openai.baseURL + "/responses")))
        await #expect(throws: InsightFailure.http(status)) { try await transport.fetch(request) }
        #expect(WebProtocol.response.withLock { $0.calls } == 1)
    }

    @Test(arguments: [false, true])
    func successfulTransportDecodesOnlyBoundedJSON(oversized: Bool) async throws {
        let payload = oversized ? Data(repeating: 65, count: 2 * 1_024 * 1_024 + 1) : Data(#"{"status":"completed"}"#.utf8)
        WebProtocol.response.withLock { $0 = .init(status: 200, mime: "application/json", data: payload) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebProtocol.self]
        let transport = URLSessionResearchTransport(allowedBaseURL: try #require(URL(string: LLMProvider.openai.baseURL)), configuration: config)
        if oversized {
            await #expect(throws: InsightFailure.oversized) { try await transport.fetch(URLRequest(url: try #require(URL(string: LLMProvider.openai.baseURL + "/responses")))) }
        } else {
            #expect(try await transport.fetch(URLRequest(url: try #require(URL(string: LLMProvider.openai.baseURL + "/responses")))) == payload)
        }
        #expect(WebProtocol.response.withLock { $0.calls } == 1)
    }

    @Test func fullWireBudgetReachesResearchDecoder() async throws {
        var payload = try nativeResearchFixture(.openai)
        payload.append(Data(repeating: 32, count: 2 * 1_024 * 1_024 - payload.count))
        WebProtocol.response.withLock { $0 = .init(status: 200, mime: "application/json", data: payload) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebProtocol.self]
        let base = try #require(URL(string: LLMProvider.openai.baseURL))
        let transport = URLSessionResearchTransport(allowedBaseURL: base, configuration: config)
        let data = try await transport.fetch(URLRequest(url: base.appendingPathComponent("responses")))
        let request = try InsightRequest(sessionID: UUID(), question: "topic", trigger: .manual, events: [])
        #expect(try LLMResearchResponse.decode(data, provider: .openai, request: request).webReferences?.count == 1)
        #expect(data.count == payload.count)
        #expect(WebProtocol.response.withLock { $0.calls } == 1)
    }

    @Test func htmlResponseIsRejected() async throws {
        WebProtocol.response.withLock { $0 = .init(status: 200, mime: "text/html", data: Data("<html>error</html>".utf8)) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebProtocol.self]
        let transport = URLSessionResearchTransport(allowedBaseURL: try #require(URL(string: LLMProvider.openai.baseURL)), configuration: config)
        let request = URLRequest(url: try #require(URL(string: LLMProvider.openai.baseURL + "/responses")))
        await #expect(throws: InsightFailure.invalidResponse) { try await transport.fetch(request) }
    }
}

final class WebProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable { let status: Int; let mime: String; let data: Data; var calls = 0 }
    static let response = Mutex(Response(status: 200, mime: "application/json", data: Data()))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let value = Self.response.withLock { state in state.calls += 1; return state }
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: value.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": value.mime]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: value.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
