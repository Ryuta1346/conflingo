import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SummaryTransportTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func completeProductRequestIsCountedAndReservedBeforeSending() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"))
        let sample = SummaryEvaluationCase(number: 1, japanese: true)
        let request = try #require(sample.plan(store: sample.store()).requests.first)
        let downstream = SummaryHTTPStub()
        downstream.ledger = ledger
        downstream.evidence = Array(sample.requiredEvidence(for: request))
        var counted: [String: Any] = [:]
        let transport = SummaryBudgetTransport(caseID: "S01-ja-1", ledger: ledger, downstream: downstream) { request in
            #expect(ledger.entries.count == 1)
            #expect(ledger.entries.last?.state == "reserved")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            counted = try #require(body["generateContentRequest"] as? [String: Any])
            return Data("{\"totalTokens\":2000}".utf8)
        }
        _ = try await GeminiInsightClient(key: { "synthetic-key" }, transport: transport).generate(request) { _ in }
        #expect(counted.removeValue(forKey: "model") as? String == "models/gemini-3.8-flash")
        let sent = try #require(downstream.requests.first?.httpBody)
        let expected = try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: sent), options: .sortedKeys)
        #expect(try JSONSerialization.data(withJSONObject: counted, options: .sortedKeys) == expected)
        #expect(ledger.entries.last?.state == "complete")
    }

    @Test(arguments: ["count-failure", "oversize", "budget", "generation-failure", "cancel-after-count"])
    func failuresNeverRetryOrSendUnreservedGeneration(reason: String) async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"), budget: reason == "budget" ? 0.001 : 2)
        let downstream = FakeInsightHTTP()
        downstream.failure = InsightFailure.offline
        var counts = 0
        let transport = SummaryBudgetTransport(caseID: "S01-ja-1", ledger: ledger, downstream: downstream) { _ in
            counts += 1
            if reason == "count-failure" { throw InsightFailure.offline }
            if reason == "cancel-after-count" { withUnsafeCurrentTask { $0?.cancel() } }
            return Data((reason == "oversize" ? "{\"totalTokens\":6001}" : "{\"totalTokens\":2000}").utf8)
        }
        let sample = SummaryEvaluationCase(number: 1, japanese: true)
        let request = try #require(sample.plan(store: sample.store()).requests.first)
        let client = GeminiInsightClient(key: { "synthetic" }, transport: transport)
        for _ in 0..<2 {
            let operation = Task { try await client.generate(request) { _ in } }
            await #expect(throws: (any Error).self) { try await operation.value }
        }
        #expect(counts == 1)
        #expect(downstream.requests.count == (reason == "generation-failure" ? 1 : 0))
        if reason == "generation-failure" { #expect(ledger.spent > 0) }
    }

    @Test func coordinatorCoversThreeSectionsAndExportsUnconfirmedEvidence() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"))
        let sample = SummaryEvaluationCase(number: 8, japanese: false)
        let store = sample.store()
        let plan = try sample.plan(store: store)
        let client = SummaryEvaluationClient(sample: sample, plan: plan, ledger: ledger, key: { "synthetic" },
            downstream: { request in
                let transport = SummaryHTTPStub()
                transport.ledger = ledger
                transport.evidence = Array(sample.requiredEvidence(for: request))
                return transport
            }, count: { _ in Data("{\"totalTokens\":2000}".utf8) })
        let coordinator = MeetingSummaryCoordinator(store: store, client: client)
        await coordinator.generate(plan, consent: true)
        let summary = try #require(coordinator.completed)
        #expect(coordinator.state == .complete)
        #expect(summary.sections.count == 3)
        #expect(client.results.count == 3)
        #expect(client.results.allSatisfy { $0.issues.isEmpty })
        #expect(sample.exportIssues(summary, plan: plan).isEmpty)
        #expect(ledger.entries.count == 6)
        #expect(summary.sections.map(\.startOffset) == [0, 300, 600])
        #expect(summary.sections.map(\.endOffset) == [295, 595, 605])
    }

    @Test func unknownUsageStopsCoordinatorBeforeSecondSection() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"))
        let sample = SummaryEvaluationCase(number: 7, japanese: true)
        let store = sample.store()
        let plan = try sample.plan(store: store)
        let client = SummaryEvaluationClient(sample: sample, plan: plan, ledger: ledger, key: { "synthetic" },
            downstream: { request in
                let transport = SummaryHTTPStub()
                transport.ledger = ledger
                transport.evidence = Array(sample.requiredEvidence(for: request))
                transport.omitUsage = true
                return transport
            }, count: { _ in Data("{\"totalTokens\":2000}".utf8) })
        let coordinator = MeetingSummaryCoordinator(store: store, client: client)
        await coordinator.generate(plan, consent: true)
        #expect(coordinator.completed == nil)
        #expect(ledger.entries.count == 2)
        #expect(ledger.entries.last?.state == "unknown")
        #expect(client.results.count == 1)
    }
}

@MainActor
private final class SummaryHTTPStub: InsightHTTPTransport {
    var ledger: SummaryBudgetLedger?
    var evidence: [UUID] = []
    var omitUsage = false
    var requests: [URLRequest] = []

    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        #expect(ledger?.entries.last?.operation == .generate)
        #expect(ledger?.entries.last?.state == "reserved")
        requests.append(request)
        let payload = try JSONSerialization.data(withJSONObject: ["kind": "answerSuggestion", "text": "Synthetic section summary.",
                                                                "evidenceIDs": evidence.map(\.uuidString)])
        let response = try geminiSSE(payload: String(decoding: payload, as: UTF8.self))
        if omitUsage {
            let raw = String(decoding: response, as: UTF8.self)
            let lines = try raw.components(separatedBy: "\n").map { line -> String in
                guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                      var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return line }
                object.removeValue(forKey: "usageMetadata")
                return "data: " + String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
            }
            try receive(Data(lines.joined(separator: "\n").utf8))
        } else {
            try receive(response)
        }
    }
}
