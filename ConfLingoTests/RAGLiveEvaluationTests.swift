import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(10)))
struct RAGLiveEvaluationTests {
    @Test(.enabled(if: RAGLiveConfiguration.enabled(ProcessInfo.processInfo.environment)))
    func approvedSyntheticCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard RAGLiveConfiguration.enabled(environment), GeminiInsightClient.model == "gemini-3.8-flash",
              let endpoint = environment["CONFLINGO_RAG_RECEIVER"].flatMap(URL.init(string:)),
              endpoint.scheme == "http", endpoint.host == "127.0.0.1", endpoint.path == "/review",
              let token = environment["CONFLINGO_RAG_RECEIVER_TOKEN"], !token.isEmpty else { throw RAGEvaluationError.configuration }
        // All retrieval checks finish before reading credentials or making any model request.
        var requests: [(RAGEvaluationCase, InsightRequest)] = []
        for sample in RAGEvaluationCase.all { requests.append((sample, try await sample.request())) }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            .appendingPathComponent("ConfLingo/Validation/pr8-quality-20261111")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = try RAGBudgetLedger(url: directory.appendingPathComponent("ledger.json"))
        // Refuse a partially consumed run rather than regenerating snapshots or silently retrying.
        guard ledger.entries.isEmpty else { throw RAGEvaluationError.duplicate }
        try await deliver(["event": "ready", "directory": directory.path], to: endpoint, token: token)
        let keyStore = KeychainAPIKeyStore()
        guard try await keyStore.read() != nil else { throw InsightFailure.missingKey }
        for (sample, request) in requests {
            let transport = RAGBudgetTransport(caseID: sample.id, ledger: ledger)
            let client = GeminiInsightClient(key: { try await keyStore.read() }, transport: transport)
            let started = ProcessInfo.processInfo.systemUptime
            do {
                let result = try await client.generate(request) { _ in }
                let issues = sample.structuralIssues(result, request: request)
                // Only the loopback reviewer receives answer text; logs and ledger contain no answer text.
                try await deliver([
                    "event": "answer", "case": sample.id, "text": result.text, "kind": result.kind.rawValue,
                    "answerLanguage": sample.answerLanguage.rawValue, "structuralIssues": issues,
                    "seconds": ProcessInfo.processInfo.systemUptime - started,
                    "references": request.knowledge.map { ["id": $0.id.uuidString, "title": $0.title, "location": $0.location, "snippet": $0.snippet] },
                    "knowledgeIDs": result.knowledgeIDs.map(\.uuidString), "evidenceIDs": result.evidenceIDs.map(\.uuidString),
                    "events": request.events.map { ["id": $0.id.uuidString, "text": $0.text] }
                ], to: endpoint, token: token)
                #expect(issues.isEmpty, "PR8 structure: \(sample.id)")
                guard ledger.entries.last?.state == "complete" else { throw RAGEvaluationError.tokens }
            } catch {
                try? await deliver(["event": "stopped", "case": sample.id, "reason": String(describing: InsightFailure.sanitized(error)),
                                    "requests": ledger.entries.count], to: endpoint, token: token)
                // Never log raw URLSession errors or model response bodies.
                throw RAGEvaluationError.response
            }
        }
        try await deliver(["event": "complete", "requests": ledger.entries.count, "estimatedUSD": ledger.spent], to: endpoint, token: token)
    }

    private func deliver(_ payload: [String: Any], to endpoint: URL, token: String) async throws {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Review-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw RAGEvaluationError.receiver }
    }
}
