import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SummaryEvaluationTests {
    @Test func fixedCorpusPreservesEveryUtteranceAndSectionBoundary() throws {
        #expect(SummaryEvaluationCase.all.count == 16)
        var sections = 0
        for sample in SummaryEvaluationCase.all {
            let store = sample.store()
            let plan = try sample.plan(store: store)
            #expect(sample.events == SummaryEvaluationCase(number: sample.number, japanese: sample.japanese).events)
            #expect(Set(sample.events.map(\.id)).count == sample.events.count)
            #expect(plan.requests.flatMap(\.events) == sample.events)
            #expect(plan.requests.allSatisfy { $0.omittedCount == 0 && $0.knowledge.isEmpty })
            let expectedCounts = sample.number == 8 ? [30, 30, 1] : sample.number == 7 ? [30, 1] : [sample.number == 5 ? 2 : 3]
            #expect(plan.requests.map { $0.events.count } == expectedCounts)
            #expect(plan.answerLanguage == (sample.japanese != (sample.number == 5) ? .japanese : .english))
            for request in plan.requests {
                #expect(!sample.requiredEvidence(for: request).isEmpty)
                #expect(sample.requiredEvidence(for: request).isSubset(of: Set(request.events.map(\.id))))
            }
            sections += plan.requests.count
        }
        #expect(sections == 22)
        #expect(Set(SummaryEvaluationCase.allowedSectionIDs).count == 22)
    }

    @Test func maximumTwentySectionsAndCharacterBoundariesRemainLocalOnly() throws {
        let session = UUID()
        let events = (0..<600).map { insightEvent(session: session, text: "Synthetic boundary", offset: Double($0)) }
        let maximum = try MeetingSummaryPlan(sessionID: session, events: events, answerLanguage: .english)
        #expect(maximum.requests.count == 20)
        #expect(maximum.requests.flatMap(\.events) == events)
        #expect(throws: (any Error).self) {
            try MeetingSummaryPlan(sessionID: session, events: events + [insightEvent(session: session, offset: 600)], answerLanguage: .english)
        }
        let exact = insightEvent(session: session, text: String(repeating: "a", count: 12_000))
        let split = try MeetingSummaryPlan(sessionID: session, events: [exact, events[1]], answerLanguage: .english)
        #expect(split.requests.map { $0.events.count } == [1, 1])
    }

    @Test func structuralScreenRejectsMissingForeignAndKnowledgeEvidence() throws {
        let sample = SummaryEvaluationCase(number: 7, japanese: true)
        let plan = try sample.plan(store: sample.store())
        let request = try #require(plan.requests.last)
        let required = Array(sample.requiredEvidence(for: request))
        let valid = InsightResult(kind: .answerSuggestion, text: "11月20日から27日へ提案を訂正。未承認です。", evidenceIDs: required)
        #expect(sample.structuralIssues(valid, request: request).isEmpty)
        let missing = InsightResult(kind: .answerSuggestion, text: valid.text, evidenceIDs: [])
        #expect(sample.structuralIssues(missing, request: request).contains("missing-evidence"))
        let foreign = InsightResult(kind: .answerSuggestion, text: valid.text, evidenceIDs: required + [sample.events[29].id])
        #expect(sample.structuralIssues(foreign, request: request).contains("invalid-evidence"))
        let knowledge = InsightResult(kind: .answerSuggestion, text: valid.text, evidenceIDs: required, knowledgeIDs: [UUID()])
        #expect(sample.structuralIssues(knowledge, request: request).contains("knowledge"))
        let empty = InsightResult(kind: .answerSuggestion, text: "", evidenceIDs: required)
        #expect(sample.structuralIssues(empty, request: request).contains("invalid-response"))
    }

    @Test func liveSuitesAreMutuallyExclusiveAndOffByDefault() {
        #expect(!SummaryLiveConfiguration.enabled([:]))
        #expect(SummaryLiveConfiguration.enabled(["CONFLINGO_SUMMARY_LIVE": "1"]))
        for flag in RAGLiveConfiguration.legacyFlags + ["CONFLINGO_RAG_LIVE"] {
            let environment = ["CONFLINGO_SUMMARY_LIVE": "1", flag: "1"]
            #expect(!SummaryLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.legacyEnabled(flag, environment))
        }
    }
}

@MainActor
struct SummaryBudgetTests {
    private func temporaryLedger() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ledger.json")
    }

    @Test func reservationSurvivesRestartAndPreventsRetryAndConcurrentRun() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var ledger: SummaryBudgetLedger? = try SummaryBudgetLedger(url: url)
        try ledger?.begin(caseID: "S01-ja-1", operation: .count, hash: "a", reservation: 0)
        try ledger?.completeCount(caseID: "S01-ja-1", tokens: 1_000)
        try ledger?.begin(caseID: "S01-ja-1", operation: .generate, hash: "a", reservation: SummaryBudgetLedger.reservation)
        #expect(throws: SummaryEvaluationError.self) { try SummaryBudgetLedger(url: url) }
        ledger = nil
        let reopened = try SummaryBudgetLedger(url: url)
        #expect(reopened.spent == SummaryBudgetLedger.reservation)
        #expect(throws: SummaryEvaluationError.self) { try reopened.requireFreshRun() }
        #expect(throws: SummaryEvaluationError.self) {
            try reopened.begin(caseID: "S01-ja-1", operation: .generate, hash: "a", reservation: SummaryBudgetLedger.reservation)
        }
    }

    @Test func insufficientBudgetAndUnapprovedIDsPreventSend() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SummaryBudgetLedger(url: url, budget: 0.01)
        try ledger.requireFreshRun()
        for invalid in ["S01-ja-2", "S09-en-1", "R01-ja"] {
            #expect(throws: SummaryEvaluationError.self) {
                try ledger.begin(caseID: invalid, operation: .count, hash: "a", reservation: 0)
            }
        }
        try ledger.begin(caseID: "S01-ja-1", operation: .count, hash: "a", reservation: 0)
        try ledger.completeCount(caseID: "S01-ja-1", tokens: 1_000)
        for amount in [SummaryBudgetLedger.reservation, 0, 0.001, -.infinity, .nan, -1] {
            #expect(throws: SummaryEvaluationError.self) {
                try ledger.begin(caseID: "S01-ja-1", operation: .generate, hash: "a", reservation: amount)
            }
        }
        #expect(ledger.entries.count == 1)
    }

    @Test func unknownUsageAndMismatchedHashStopSubsequentSections() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SummaryBudgetLedger(url: url)
        try ledger.begin(caseID: "S07-ja-1", operation: .count, hash: "a", reservation: 0)
        try ledger.completeCount(caseID: "S07-ja-1", tokens: 1_000)
        #expect(throws: SummaryEvaluationError.self) {
            try ledger.begin(caseID: "S07-ja-1", operation: .generate, hash: "b", reservation: SummaryBudgetLedger.reservation)
        }
        try ledger.begin(caseID: "S07-ja-1", operation: .generate, hash: "a", reservation: SummaryBudgetLedger.reservation)
        try ledger.completeGeneration(caseID: "S07-ja-1", usage: nil)
        #expect(ledger.spent == SummaryBudgetLedger.reservation)
        #expect(throws: SummaryEvaluationError.self) {
            try ledger.begin(caseID: "S07-ja-2", operation: .count, hash: "b", reservation: 0)
        }
    }

    @Test(arguments: [InsightUsage(inputTokens: 6_001, outputTokens: 1, thinkingTokens: 0),
                      InsightUsage(inputTokens: 100, outputTokens: 8_000, thinkingTokens: 193)])
    func usageBeyondApprovedLimitsStopsFurtherRequests(usage: InsightUsage) throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SummaryBudgetLedger(url: url)
        try ledger.begin(caseID: "S01-ja-1", operation: .count, hash: "a", reservation: 0)
        try ledger.completeCount(caseID: "S01-ja-1", tokens: 1_000)
        try ledger.begin(caseID: "S01-ja-1", operation: .generate, hash: "a", reservation: SummaryBudgetLedger.reservation)
        try ledger.completeGeneration(caseID: "S01-ja-1", usage: usage)
        #expect(ledger.entries.last?.state == "limit-exceeded")
        #expect(ledger.spent > 0)
        #expect(throws: SummaryEvaluationError.self) {
            try ledger.begin(caseID: "S01-en-1", operation: .count, hash: "b", reservation: 0)
        }
    }

    @Test func exactlyTwentyTwoSectionsHaveIndependentCountAndGenerationSlots() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try SummaryBudgetLedger(url: url)
        for section in SummaryEvaluationCase.allowedSectionIDs {
            try ledger.begin(caseID: section, operation: .count, hash: section, reservation: 0)
            try ledger.completeCount(caseID: section, tokens: 1_000)
            try ledger.begin(caseID: section, operation: .generate, hash: section, reservation: SummaryBudgetLedger.reservation)
            try ledger.completeGeneration(caseID: section, usage: InsightUsage(inputTokens: 1_000, outputTokens: 100, thinkingTokens: 100))
        }
        #expect(ledger.entries.count == 44)
        #expect(abs(ledger.spent - 0.033) < 0.0000001)
        #expect(throws: SummaryEvaluationError.self) {
            try ledger.begin(caseID: "S08-en-3", operation: .count, hash: "repeat", reservation: 0)
        }
    }
}
