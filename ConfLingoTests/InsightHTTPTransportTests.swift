import Foundation
import Synchronization
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InsightHTTPTransportTests {
    @Test(arguments: [401, 403, 429, 500, 302])
    func httpErrorsRemainTypedWithoutRetry(status: Int) async throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/test/\(UUID())"))
        TestInsightURLProtocol.fixtures.withLock { $0[url.path] = .init(status: status, body: Data("private error body".utf8)) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[url.path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        let transport = URLSessionInsightTransport(configuration: config)
        var received = Data()
        await #expect(throws: InsightFailure.http(status)) {
            try await transport.stream(URLRequest(url: url)) { received.append($0) }
        }
        #expect(received.isEmpty)
        #expect(TestInsightURLProtocol.fixtures.withLock { $0[url.path]?.calls } == 1)
    }

    @Test func transportFeedsTheRealGeminiDecoderWithoutExternalNetwork() async throws {
        let event = insightEvent()
        let request = try InsightRequest(sessionID: event.sessionID, question: "What next?", trigger: .manual, events: [event])
        let path = "/v1beta/models/\(GeminiInsightClient.model):streamGenerateContent"
        let payload = "{\"text\":\"Check the owner\",\"kind\":\"followUpQuestion\",\"evidenceIDs\":[\"\(event.id)\"]}"
        TestInsightURLProtocol.fixtures.withLock { $0[path] = .init(status: 200, body: (try? geminiSSE(payload: payload)) ?? Data()) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        let client = GeminiInsightClient(key: { "synthetic-key" }, transport: URLSessionInsightTransport(configuration: config))
        let result = try await client.generate(request) { _ in }
        #expect(result.text == "Check the owner")
        #expect(result.evidenceIDs == [event.id])
    }

    @Test func fragmentedLongAnswerPassesThroughRealTransportAndDecoder() async throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/test/\(UUID())"))
        let answer = String(repeating: "あ", count: 8_000)
        let stream = try responseStream(.gemini, payload: responsePayload(answer), charactersPerEvent: 1)
        TestInsightURLProtocol.fixtures.withLock { $0[url.path] = .init(status: 200, body: stream) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[url.path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        var decoder = GeminiStreamDecoder()
        try await URLSessionInsightTransport(configuration: config).stream(URLRequest(url: url)) { try decoder.consume($0) }
        #expect(try decoder.finish().text == answer)
    }

    @Test(arguments: [false, true])
    func transportRetainsFiniteWireBudget(overflow: Bool) async throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/test/\(UUID())"))
        let budget = 2 * 1_024 * 1_024
        let data = Data(repeating: 32, count: budget + (overflow ? 1 : 0))
        TestInsightURLProtocol.fixtures.withLock { $0[url.path] = .init(status: 200, body: data) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[url.path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        let transport = URLSessionInsightTransport(configuration: config)
        var received = 0
        if overflow {
            await #expect(throws: InsightFailure.oversized) { try await transport.stream(URLRequest(url: url)) { received += $0.count } }
        } else {
            try await transport.stream(URLRequest(url: url)) { received += $0.count }
        }
        #expect(received == budget)
        #expect(TestInsightURLProtocol.fixtures.withLock { $0[url.path]?.calls } == 1)
    }

    @Test func decoderFailureStopsCallbacksImmediately() async throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/test/\(UUID())"))
        TestInsightURLProtocol.fixtures.withLock { $0[url.path] = .init(status: 200, body: Data(repeating: 32, count: 300_000)) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[url.path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        var calls = 0
        await #expect(throws: InsightFailure.oversized) {
            try await URLSessionInsightTransport(configuration: config).stream(URLRequest(url: url)) { _ in
                calls += 1
                throw InsightFailure.oversized
            }
        }
        #expect(calls == 1)
    }

    @Test func redirectsNeverForwardCredentials() async throws {
        let source = try #require(URL(string: "https://generativelanguage.googleapis.com/test"))
        let target = try #require(URL(string: "https://example.invalid/collect"))
        let response = try #require(HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: nil))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: source)
        let redirected = await withCheckedContinuation { continuation in
            InsightRedirectGuard().urlSession(session, task: task, willPerformHTTPRedirection: response,
                                               newRequest: URLRequest(url: target)) { request in
                continuation.resume(returning: request)
            }
        }
        #expect(redirected == nil)
    }
}

final class TestInsightURLProtocol: URLProtocol, @unchecked Sendable {
    struct Fixture: Sendable {
        let status: Int
        let body: Data
        var calls = 0
    }
    static let fixtures = Mutex<[String: Fixture]>([:])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let fixture = Self.fixtures.withLock { state -> Fixture? in
            state[url.path]?.calls += 1
            return state[url.path]
        }
        guard let fixture, let response = HTTPURLResponse(url: url, statusCode: fixture.status,
                                                          httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
