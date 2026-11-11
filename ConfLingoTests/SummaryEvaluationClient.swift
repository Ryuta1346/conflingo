import Foundation
@testable import ConfLingo

@MainActor
final class SummaryEvaluationClient: InsightClient {
    struct Observation {
        let sectionID: String
        let request: InsightRequest
        let result: InsightResult
        let issues: [String]
        let seconds: Double
    }
    private let sample: SummaryEvaluationCase
    private let plan: MeetingSummaryPlan
    private let ledger: SummaryBudgetLedger
    private let key: @MainActor () async throws -> String?
    private let downstream: @MainActor (InsightRequest) -> any InsightHTTPTransport
    private let count: @MainActor (URLRequest) async throws -> Data
    private let saveTiming: ((SummaryTiming.Snapshot) throws -> Void)?
    private var timingStorageFailed = false
    var observe: @MainActor (Observation) async throws -> Void = { _ in }
    private(set) var results: [Observation] = []

    init(sample: SummaryEvaluationCase, plan: MeetingSummaryPlan, ledger: SummaryBudgetLedger,
         key: @escaping @MainActor () async throws -> String?,
         downstream: @escaping @MainActor (InsightRequest) -> any InsightHTTPTransport = { _ in URLSessionInsightTransport() },
         count: @escaping @MainActor (URLRequest) async throws -> Data = RAGCountHTTP.send,
         saveTiming: ((SummaryTiming.Snapshot) throws -> Void)? = nil) {
        self.sample = sample
        self.plan = plan
        self.ledger = ledger
        self.key = key
        self.downstream = downstream
        self.count = count
        self.saveTiming = saveTiming
    }

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        let index = results.count
        guard !timingStorageFailed, index < plan.requests.count, plan.requests[index].id == request.id else {
            throw SummaryEvaluationError.configuration
        }
        let sectionID = "\(sample.id)-\(index + 1)"
        let timing = saveTiming == nil ? nil : SummaryTiming(sectionID: sectionID)
        let transport = SummaryBudgetTransport(caseID: sectionID, ledger: ledger, downstream: downstream(request), timing: timing, count: count)
        let client = GeminiInsightClient(key: key, transport: transport)
        let started = ProcessInfo.processInfo.systemUptime
        let result: InsightResult
        do {
            result = try await client.generate(request) { text in
                timing?.preview(characters: text.count)
                update(text)
            }
            let observation = Observation(sectionID: sectionID, request: request, result: result,
                                          issues: sample.structuralIssues(result, request: request),
                                          seconds: ProcessInfo.processInfo.systemUptime - started)
            results.append(observation)
            timing?.mark(.observerStart)
            try await observe(observation)
            timing?.mark(.observerEnd)
            try Task.checkCancellation()
            guard ledger.entries.last?.state == "complete" else { throw SummaryEvaluationError.tokens }
        } catch {
            timing?.finish(outcome: Task.isCancelled ? "cancelled" : "failed", failure: String(describing: InsightFailure.sanitized(error)))
            try persist(timing)
            throw error
        }
        timing?.finish(outcome: "complete")
        try persist(timing)
        return result
    }

    private func persist(_ timing: SummaryTiming?) throws {
        guard let timing else { return }
        do { try saveTiming?(timing.snapshot) } catch {
            timingStorageFailed = true
            throw SummaryEvaluationError.ledger
        }
    }
}

extension SummaryEvaluationCase {
    func exportIssues(_ summary: MeetingSummary, plan: MeetingSummaryPlan) -> [String] {
        guard summary.sessionID == plan.sessionID, summary.answerLanguage == plan.answerLanguage,
              summary.sections.count == plan.requests.count else { return ["summary-shape"] }
        let snapshot = MeetingExportSnapshot(title: id, startedAt: nil, microphoneLocale: japanese ? "ja-JP" : "en-US",
                                             systemLocale: japanese ? "ja-JP" : "en-US", sessionID: plan.sessionID,
                                             events: plan.events, candidates: [], summary: summary)
        let markdown = snapshot.markdown
        var issues: [String] = []
        if !markdown.contains("## AIによる区間別要約（未確認）")
            || !markdown.contains("各区間の記述は会議全体の最終合意を表しません。") { issues.append("unconfirmed-label") }
        for (section, request) in zip(summary.sections, plan.requests) {
            if section.id != request.id || section.startOffset != request.events.first?.startOffset
                || section.endOffset != request.events.map({ $0.endOffset ?? $0.startOffset }).max() { issues.append("section-range") }
            if !requiredEvidence(for: request).isSubset(of: Set(section.evidenceIDs)) { issues.append("export-evidence") }
            if !Set(section.evidenceIDs).isSubset(of: Set(request.events.map(\.id))) { issues.append("foreign-evidence") }
            for evidence in section.evidenceIDs {
                let anchor = "utterance-" + evidence.uuidString.lowercased()
                if !markdown.contains("](#\(anchor))") || !markdown.contains("<a id=\"\(anchor)\"></a>") { issues.append("anchor") }
            }
        }
        return issues
    }
}
