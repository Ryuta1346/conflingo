import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SummaryDeadlineTests {
    @Test func onlySummaryHTTPRequestsReceiveSixtySeconds() async throws {
        let store = summaryStore(count: 31)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english)
        let manual = try InsightRequest(sessionID: store.sessionID, question: "Next?", trigger: .manual, events: store.finals)
        let automatic = try InsightRequest(sessionID: store.sessionID, question: "Next?", trigger: .automatic, events: store.finals)
        let rag = try await RAGEvaluationCase(number: 1, japanese: false).request()
        for (request, seconds) in [(manual, 30.0), (automatic, 30.0), (rag, 30.0)] + plan.requests.map({ ($0, 60.0) }) {
            #expect(request.timeoutSeconds == seconds)
            let transport = FakeInsightHTTP()
            transport.chunks = [try geminiSSE(payload: "{\"text\":\"Synthetic\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}")]
            _ = try await GeminiInsightClient(key: { "synthetic-key" }, transport: transport).generate(request) { _ in }
            #expect(transport.requests.first?.timeoutInterval == seconds)
        }
    }

    @Test(arguments: [30.0, 60.0])
    func sessionRequestAndResourceDeadlinesFollowHTTP(seconds: Double) async throws {
        let url = try #require(URL(string: "https://generativelanguage.googleapis.com/test/\(UUID())"))
        TestInsightURLProtocol.fixtures.withLock { $0[url.path] = .init(status: 200, body: Data()) }
        defer { TestInsightURLProtocol.fixtures.withLock { $0[url.path] = nil } }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TestInsightURLProtocol.self]
        let transport = URLSessionInsightTransport(configuration: config)
        try await transport.stream(URLRequest(url: url, timeoutInterval: seconds)) { _ in }
        #expect(config.timeoutIntervalForRequest == seconds)
        #expect(config.timeoutIntervalForResource == seconds)
    }

    @Test func defaultSummaryDeadlineAllowsCompletionBeyondThirtySeconds() async throws {
        let store = summaryStore(count: 1)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english)
        let client = DeadlineSummaryClient()
        client.delay = .seconds(31)
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        await summary.generate(plan, consent: true)
        #expect(summary.state == .complete && summary.completed?.sections.count == 1)
        #expect(!client.cancelled)
    }

    @Test func longerDeadlineCompletesButExpiryStillStopsAndPreservesPreviousSummary() async throws {
        let store = summaryStore(count: 31)
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .english)
        let client = DeadlineSummaryClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client, timeout: .milliseconds(300))
        await summary.generate(plan, consent: true)
        #expect(summary.state == .complete)
        let completed = try #require(summary.completed)
        #expect(completed.sections.count == 2)
        client.delay = .seconds(60)
        await summary.generate(plan, consent: true)
        #expect(summary.state == .failed(.timeout))
        #expect(summary.completed == completed)
        #expect(client.calls == 3 && client.cancelled)
        #expect(summary.partialText.isEmpty)
    }
}

@MainActor
private final class DeadlineSummaryClient: InsightClient {
    var delay: Duration = .milliseconds(50)
    var calls = 0
    var cancelled = false
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        calls += 1
        update("Synthetic preview")
        do { try await Task.sleep(for: delay) } catch { cancelled = true; throw error }
        return InsightResult(kind: .answerSuggestion, text: "Synthetic summary", evidenceIDs: request.events.map(\.id))
    }
}
