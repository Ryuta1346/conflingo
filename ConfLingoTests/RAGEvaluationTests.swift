import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct RAGEvaluationTests {
    @Test func allApprovedCasesRetrieveExpectedSnapshotsBeforeAnyNetwork() async throws {
        #expect(RAGEvaluationCase.all.count == 16)
        #expect(Set(RAGEvaluationCase.all.map(\.id)).count == 16)
        for sample in RAGEvaluationCase.all {
            let request = try await sample.request()
            #expect(sample.retrievalIssues(request).isEmpty, "Retrieval: \(sample.id)")
            #expect(request.trigger == .manual)
            #expect(request.answerLanguage == sample.answerLanguage)
            #expect(request.events.count == (sample.number == 6 ? 1 : 0))
        }
    }

    @Test func structuralScreenRejectsWrongAndMissingCitationsAndCandidates() async throws {
        let sample = RAGEvaluationCase(number: 2, japanese: true)
        let request = try await sample.request()
        let good = InsightResult(kind: .answerSuggestion, text: "The price is JPY 1200 per month. Support hours are 09:00 to 17:00 on weekdays.",
                                 evidenceIDs: [], knowledgeIDs: request.knowledge.map(\.id))
        #expect(sample.structuralIssues(good, request: request).isEmpty)
        var bad = good
        bad.knowledgeIDs = []
        #expect(sample.structuralIssues(bad, request: request).contains("citation-set"))
        bad.knowledgeIDs = [UUID()]
        #expect(sample.structuralIssues(bad, request: request).contains("invalid-evidence"))
        let candidate = InsightResult(kind: .decisionCandidate, text: "Adopt Orion.", evidenceIDs: [], knowledgeIDs: request.knowledge.map(\.id))
        #expect(sample.structuralIssues(candidate, request: request).contains("kind"))
    }

    @Test func legacyAndRAGLiveSuitesCannotBeEnabledTogether() {
        #expect(!RAGLiveConfiguration.enabled([:]))
        #expect(RAGLiveConfiguration.enabled(["CONFLINGO_RAG_LIVE": "1"]))
        #expect(!RAGLiveConfiguration.enabled(["CONFLINGO_RAG_LIVE": "1", "CONFLINGO_LIVE_AI": "1"]))
        for flag in RAGLiveConfiguration.legacyFlags {
            let mixed = ["CONFLINGO_RAG_LIVE": "1", flag: "1"]
            #expect(!RAGLiveConfiguration.enabled(mixed))
            #expect(!RAGLiveConfiguration.legacyEnabled(flag, mixed))
        }
    }
}

@MainActor
struct RAGBudgetTests {
    private func temporaryLedger() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ledger.json")
    }

    @Test func failedRequestsRemainReservedAcrossRestartAndCannotBeRetried() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var ledger: RAGBudgetLedger? = try RAGBudgetLedger(url: url)
        try ledger?.begin(caseID: "R01-ja", operation: .count, hash: "snapshot", reservation: 0)
        try ledger?.completeCount(caseID: "R01-ja", tokens: 1_000)
        try ledger?.begin(caseID: "R01-ja", operation: .generate, hash: "snapshot", reservation: 0.04)
        #expect(throws: RAGEvaluationError.self) { try RAGBudgetLedger(url: url) }
        ledger = nil
        let reopened = try RAGBudgetLedger(url: url)
        #expect(reopened.spent == 0.04)
        #expect(reopened.entries.count == 2)
        #expect(throws: RAGEvaluationError.self) {
            try reopened.begin(caseID: "R01-ja", operation: .generate, hash: "snapshot", reservation: 0.04)
        }
    }

    @Test func budgetLimitAndInvalidAmountsPreventReservation() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try RAGBudgetLedger(url: url, budget: 0.01)
        try ledger.begin(caseID: "R01-ja", operation: .count, hash: "snapshot", reservation: 0)
        try ledger.completeCount(caseID: "R01-ja", tokens: 1_000)
        for amount in [0.02, -.infinity, .nan, -1] {
            #expect(throws: RAGEvaluationError.self) {
                try ledger.begin(caseID: "R01-ja", operation: .generate, hash: "snapshot", reservation: amount)
            }
        }
        #expect(ledger.entries.count == 1)
    }

    @Test func generationRequiresSuccessfulMatchingCountAndUsageSettlesOnlyKnownCost() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try RAGBudgetLedger(url: url)
        #expect(throws: RAGEvaluationError.self) {
            try ledger.begin(caseID: "R01-ja", operation: .generate, hash: "a", reservation: 0.04)
        }
        try ledger.begin(caseID: "R01-ja", operation: .count, hash: "a", reservation: 0)
        try ledger.completeCount(caseID: "R01-ja", tokens: 1_000)
        #expect(throws: RAGEvaluationError.self) {
            try ledger.begin(caseID: "R01-ja", operation: .generate, hash: "b", reservation: 0.04)
        }
        try ledger.begin(caseID: "R01-ja", operation: .generate, hash: "a", reservation: 0.04)
        try ledger.completeGeneration(caseID: "R01-ja", usage: nil)
        #expect(ledger.spent == 0.04)
        #expect(throws: RAGEvaluationError.self) {
            try ledger.begin(caseID: "R02-ja", operation: .count, hash: "b", reservation: 0)
        }
    }

    @Test func allSixteenCasesHaveSeparateCountAndGenerationLimits() throws {
        let url = try temporaryLedger()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let ledger = try RAGBudgetLedger(url: url)
        for sample in RAGEvaluationCase.all {
            try ledger.begin(caseID: sample.id, operation: .count, hash: sample.id, reservation: 0)
            try ledger.completeCount(caseID: sample.id, tokens: 1_000)
            try ledger.begin(caseID: sample.id, operation: .generate, hash: sample.id, reservation: 0.04)
            try ledger.completeGeneration(caseID: sample.id, usage: InsightUsage(inputTokens: 1_000, outputTokens: 100, thinkingTokens: 100))
        }
        #expect(ledger.entries.count == 32)
        #expect(abs(ledger.spent - 0.024) < 0.0000001)
        #expect(throws: RAGEvaluationError.self) {
            try ledger.begin(caseID: "R09-ja", operation: .count, hash: "extra", reservation: 0)
        }
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!saved.contains("x-goog-api-key"))
        #expect(!saved.contains("snippet"))
    }
}
