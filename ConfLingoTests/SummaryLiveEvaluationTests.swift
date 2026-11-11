import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(15)))
struct SummaryLiveEvaluationTests {
    @Test(.enabled(if: SummaryLiveConfiguration.enabled(ProcessInfo.processInfo.environment)))
    func approvedSyntheticSummaries() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let run = SummaryLiveConfiguration.run(environment), GeminiInsightClient.model == "gemini-3.8-flash",
              let endpoint = environment["CONFLINGO_SUMMARY_RECEIVER"].flatMap(URL.init(string:)),
              endpoint.scheme == "http", endpoint.host == "127.0.0.1", endpoint.path == "/review",
              let token = environment["CONFLINGO_SUMMARY_RECEIVER_TOKEN"], !token.isEmpty else { throw SummaryEvaluationError.configuration }
        var corpus: [(SummaryEvaluationCase, MeetingSessionStore, MeetingSummaryPlan)] = []
        for sample in run.cases {
            let store = sample.store()
            let plan = try sample.plan(store: store)
            guard plan.requests.count == sample.sectionCount, plan.requests.flatMap(\.events) == sample.events,
                  plan.requests.allSatisfy({ $0.omittedCount == 0 && $0.knowledge.isEmpty
                      && $0.timeoutSeconds == 60 && !sample.requiredEvidence(for: $0).isEmpty }) else { throw SummaryEvaluationError.configuration }
            corpus.append((sample, store, plan))
        }
        guard corpus.count == run.cases.count, corpus.reduce(0, { $0 + $1.2.requests.count }) == run.sectionIDs.count else { throw SummaryEvaluationError.configuration }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
            .appendingPathComponent("ConfLingo/Validation/\(run.id)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"), run: run)
        try ledger.requireFreshRun()
        try await deliver(["event": "ready", "directory": directory.path], to: endpoint, token: token)
        let keyStore = KeychainAPIKeyStore()
        guard try await keyStore.read() != nil else { throw InsightFailure.missingKey }
        var caseStates: [[String: Any]] = []
        let saveTiming: ((SummaryTiming.Snapshot) throws -> Void)? = run != .initial ? { snapshot in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(snapshot).write(to: directory.appendingPathComponent("\(snapshot.sectionID)-timing.json"), options: .atomic)
        } : nil
        for (sample, store, plan) in corpus {
            let client = SummaryEvaluationClient(sample: sample, plan: plan, ledger: ledger,
                                                 key: { try await keyStore.read() }, saveTiming: saveTiming)
            client.observe = { observation in
                try await deliver([
                    "event": "answer", "case": sample.id, "section": observation.sectionID,
                    "text": observation.result.text, "kind": observation.result.kind.rawValue,
                    "answerLanguage": sample.answerLanguage.rawValue, "structuralIssues": observation.issues,
                    "seconds": observation.seconds,
                    "evidenceIDs": observation.result.evidenceIDs.map(\.uuidString),
                    "requiredEvidenceIDs": sample.requiredEvidence(for: observation.request).map(\.uuidString).sorted(),
                    "events": observation.request.events.map { ["id": $0.id.uuidString, "text": $0.text] }
                ], to: endpoint, token: token)
                #expect(observation.issues.isEmpty, "PR7 structure: \(observation.sectionID)")
            }
            let coordinator = MeetingSummaryCoordinator(store: store, client: client)
            let caseStarted = ProcessInfo.processInfo.systemUptime
            await coordinator.generate(plan, consent: true)
            if run != .initial {
                caseStates.append(["case": sample.id, "coordinatorState": String(describing: coordinator.state),
                                   "seconds": ProcessInfo.processInfo.systemUptime - caseStarted,
                                   "completedSections": coordinator.completed?.sections.count ?? 0,
                                   "draftSections": coordinator.draft.count])
                try JSONSerialization.data(withJSONObject: caseStates, options: [.prettyPrinted, .sortedKeys])
                    .write(to: directory.appendingPathComponent("case-states.json"), options: .atomic)
            }
            guard coordinator.state == .complete, let summary = coordinator.completed,
                  client.results.count == plan.requests.count, ledger.entries.last?.state == "complete" else {
                try? await deliver(["event": "stopped", "case": sample.id, "requests": ledger.entries.count,
                                    "reason": String(describing: coordinator.state)], to: endpoint, token: token)
                throw SummaryEvaluationError.response
            }
            let issues = sample.exportIssues(summary, plan: plan)
            #expect(issues.isEmpty, "PR7 export: \(sample.id)")
            try await deliver(["event": "case-complete", "case": sample.id, "exportIssues": issues,
                               "sections": summary.sections.count], to: endpoint, token: token)
        }
        #expect(ledger.entries.count == run.sectionIDs.count * 2)
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
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration, delegate: InsightRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 204 else { throw SummaryEvaluationError.receiver }
    }
}
