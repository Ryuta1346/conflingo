import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SummaryRemainingTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test(arguments: [SummaryEvaluationRun.remaining, .deadline])
    func remainingRunHasFixedOrderAndOnlyEightAuthorizedSections(run: SummaryEvaluationRun) throws {
        #expect(run.cases.map(\.id) == ["S08-ja", "S08-en", "S07-en"])
        #expect(run.sectionIDs == ["S08-ja-1", "S08-ja-2", "S08-ja-3", "S08-en-1", "S08-en-2", "S08-en-3", "S07-en-1", "S07-en-2"])
        #expect(run.budgetUSD == 1)
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"), run: run)
        for id in ["S01-ja-1", "S07-ja-1", "S08-en-4"] {
            #expect(throws: SummaryEvaluationError.self) { try ledger.begin(caseID: id, operation: .count, hash: "a", reservation: 0) }
        }
        for id in run.sectionIDs {
            try ledger.begin(caseID: id, operation: .count, hash: id, reservation: 0)
            try ledger.completeCount(caseID: id, tokens: 1_000)
            try ledger.begin(caseID: id, operation: .generate, hash: id, reservation: SummaryBudgetLedger.reservation)
            try ledger.completeGeneration(caseID: id, usage: InsightUsage(inputTokens: 1_000, outputTokens: 100, thinkingTokens: 100))
        }
        #expect(ledger.entries.count == 16)
        #expect(throws: SummaryEvaluationError.self) { try ledger.requireFreshRun() }
        #expect(throws: SummaryEvaluationError.self) {
            try ledger.begin(caseID: "S08-ja-1", operation: .count, hash: "repeat", reservation: 0)
        }
    }

    @Test func deadlineRunIsIsolatedFromBothPreviousRunsAndEveryLiveFlag() throws {
        let run = SummaryEvaluationRun.deadline
        #expect(run.id == "pr7-summary-deadline-20261111")
        #expect(run.flag == "CONFLINGO_SUMMARY_DEADLINE_LIVE")
        #expect(SummaryLiveConfiguration.run([run.flag: "1"]) == .deadline)
        for flag in RAGLiveConfiguration.legacyFlags + ["CONFLINGO_RAG_LIVE", "CONFLINGO_SUMMARY_LIVE", "CONFLINGO_SUMMARY_REMAINING_LIVE"] {
            let environment = [run.flag: "1", flag: "1"]
            #expect(!SummaryLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.legacyEnabled(flag, environment))
        }
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        for previous in [SummaryEvaluationRun.initial, .remaining] {
            let url = directory.appendingPathComponent(previous.id + ".json")
            var ledger: SummaryBudgetLedger? = try SummaryBudgetLedger(url: url, run: previous)
            try ledger?.begin(caseID: "S08-en-1", operation: .count, hash: "old", reservation: 0)
            try ledger?.completeCount(caseID: "S08-en-1", tokens: 1000)
            try ledger?.begin(caseID: "S08-en-1", operation: .generate, hash: "old", reservation: SummaryBudgetLedger.reservation)
            ledger = nil
            let before = try Data(contentsOf: url)
            #expect(throws: SummaryEvaluationError.self) { try SummaryBudgetLedger(url: url, run: run) }
            #expect(try Data(contentsOf: url) == before)
        }
        #expect(throws: SummaryEvaluationError.self) {
            try SummaryBudgetLedger(url: directory.appendingPathComponent("over.json"), run: run, budget: 1.01)
        }
    }

    @Test func runIdentityMismatchNeverRewritesPreviousLedger() throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ledger.json")
        var initial: SummaryBudgetLedger? = try SummaryBudgetLedger(url: url)
        try initial?.begin(caseID: "S07-en-1", operation: .count, hash: "original", reservation: 0)
        try initial?.completeCount(caseID: "S07-en-1", tokens: 3_633)
        try initial?.begin(caseID: "S07-en-1", operation: .generate, hash: "original", reservation: SummaryBudgetLedger.reservation)
        initial = nil
        let before = try Data(contentsOf: url)
        #expect(throws: SummaryEvaluationError.self) { try SummaryBudgetLedger(url: url, run: .remaining) }
        let reopened = try SummaryBudgetLedger(url: url)
        #expect(reopened.spent == SummaryBudgetLedger.reservation)
        #expect(throws: SummaryEvaluationError.self) { try reopened.requireFreshRun() }
        #expect(try Data(contentsOf: url) == before)
        #expect(throws: SummaryEvaluationError.self) {
            try SummaryBudgetLedger(url: directory.appendingPathComponent("extra.json"), run: .remaining, budget: 1.01)
        }
    }

    @Test func remainingFlagExcludesEveryOtherLiveSuite() {
        #expect(SummaryLiveConfiguration.run(["CONFLINGO_SUMMARY_REMAINING_LIVE": "1"]) == .remaining)
        #expect(SummaryLiveConfiguration.run(["CONFLINGO_SUMMARY_LIVE": "1"]) == .initial)
        for flag in RAGLiveConfiguration.legacyFlags + ["CONFLINGO_RAG_LIVE", "CONFLINGO_SUMMARY_LIVE"] {
            let environment = ["CONFLINGO_SUMMARY_REMAINING_LIVE": "1", flag: "1"]
            #expect(!SummaryLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.enabled(environment))
            #expect(!RAGLiveConfiguration.legacyEnabled(flag, environment))
        }
    }
}

@MainActor
struct SummaryTimingTests {
    @Test func milestonesUseMonotonicTimeAndKeepUnobservedStagesNull() throws {
        var now = 100.0
        let timing = SummaryTiming(sectionID: "S08-ja-1", clock: { now })
        now = 101
        timing.mark(.transport)
        timing.mark(.countStart)
        now = 102
        timing.mark(.countEnd)
        timing.mark(.generationStart)
        now = 105
        timing.receive(bytes: 20)
        now = 106
        timing.preview(characters: 5)
        now = 107
        timing.receive(bytes: 30)
        timing.preview(characters: 2)
        timing.finish(outcome: "cancelled")
        let snapshot = timing.snapshot
        #expect(snapshot.times["clientStart"] == 0)
        #expect(snapshot.times["firstChunk"] == 5)
        #expect(snapshot.times["lastChunk"] == 7)
        #expect(snapshot.times["firstPreview"] == 6)
        #expect(snapshot.chunkCount == 2 && snapshot.receivedBytes == 50 && snapshot.maxPreviewCharacters == 5)
        #expect(snapshot.outcome == "cancelled")
        let data = try JSONEncoder().encode(snapshot)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let times = try #require(object["times"] as? [String: Any])
        #expect(times["streamEnd"] is NSNull)
        #expect(!String(decoding: data, as: UTF8.self).contains("synthetic-key"))
    }

    @Test(arguments: [false, true])
    func timeoutRecordsWhetherDataArrivedAndStopsLaterSections(received: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"), run: .remaining)
        let sample = SummaryEvaluationCase(number: 8, japanese: true)
        let store = sample.store()
        let plan = try sample.plan(store: store)
        let downstream = TimingHTTPStub(mode: received ? .partialThenWait : .wait)
        var saved: [SummaryTiming.Snapshot] = []
        let client = SummaryEvaluationClient(sample: sample, plan: plan, ledger: ledger, key: { "synthetic-key" },
            downstream: { _ in downstream }, count: { _ in Data("{\"totalTokens\":1000}".utf8) }, saveTiming: { saved.append($0) })
        let coordinator = MeetingSummaryCoordinator(store: store, client: client, timeout: .milliseconds(100))
        await coordinator.generate(plan, consent: true)
        #expect(coordinator.state == .failed(.timeout))
        #expect(downstream.calls == 1 && ledger.entries.count == 2)
        let timing = try #require(saved.first)
        #expect(saved.count == 1 && timing.outcome == "cancelled")
        #expect((timing.chunkCount > 0) == received)
        #expect(timing.times["streamEnd"] == .some(nil))
        #expect(coordinator.completed == nil)
    }

    @Test(arguments: ["success", "usage-missing", "save-failure", "slow-observer"])
    func completionAndPostprocessingAreMeasuredWithoutLosingFailureSafety(mode: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ledger = try SummaryBudgetLedger(url: directory.appendingPathComponent("ledger.json"), run: .remaining)
        let sample = SummaryEvaluationCase(number: 7, japanese: false)
        let store = sample.store()
        let plan = try sample.plan(store: store)
        var saved: [SummaryTiming.Snapshot] = []
        let client = SummaryEvaluationClient(sample: sample, plan: plan, ledger: ledger, key: { "synthetic-key" },
            downstream: { request in TimingHTTPStub(mode: mode == "usage-missing" ? .noUsage : .complete, evidence: request.events.map(\.id)) },
            count: { _ in Data("{\"totalTokens\":1000}".utf8) }, saveTiming: { snapshot in
                if mode == "save-failure" { throw SummaryEvaluationError.ledger }
                saved.append(snapshot)
            })
        if mode == "slow-observer" { client.observe = { _ in try await Task.sleep(for: .seconds(60)) } }
        let coordinator = MeetingSummaryCoordinator(store: store, client: client, timeout: .milliseconds(100))
        await coordinator.generate(plan, consent: true)
        if mode == "success" {
            #expect(coordinator.state == .complete && saved.count == 2)
            #expect(saved.allSatisfy { $0.outcome == "complete" && $0.times["usageSettled"] != .some(nil) })
        } else {
            #expect(coordinator.completed == nil)
            #expect(ledger.entries.count == 2)
            if mode != "save-failure" {
                let timing = try #require(saved.first)
                #expect(timing.times["streamEnd"] != .some(nil))
                if mode == "slow-observer" {
                    #expect(coordinator.state == .failed(.timeout))
                    #expect(timing.times["observerStart"] != .some(nil) && timing.times["observerEnd"] == .some(nil))
                }
            }
        }
    }
}

@MainActor
private final class TimingHTTPStub: InsightHTTPTransport {
    enum Mode { case wait, partialThenWait, complete, noUsage }
    let mode: Mode
    let evidence: [UUID]
    var calls = 0
    init(mode: Mode, evidence: [UUID] = []) { self.mode = mode; self.evidence = evidence }
    func stream(_ request: URLRequest, receive: @escaping @MainActor (Data) throws -> Void) async throws {
        calls += 1
        if mode == .wait { try await Task.sleep(for: .seconds(60)); return }
        if mode == .partialThenWait {
            let content: [String: Any] = ["parts": [["text": "{\"text\":\"Synthetic"]]]
            let frame: [String: Any] = ["candidates": [["index": 0, "content": content]]]
            try receive(Data("data: ".utf8) + JSONSerialization.data(withJSONObject: frame) + Data("\n\n".utf8))
            try await Task.sleep(for: .seconds(60))
            return
        }
        let payload = try JSONSerialization.data(withJSONObject: ["text": "Synthetic summary.", "kind": "answerSuggestion", "evidenceIDs": evidence.map(\.uuidString)])
        let frame: [String: Any] = ["candidates": [["index": 0, "content": ["parts": [["text": String(decoding: payload, as: UTF8.self)]]], "finishReason": "STOP"]]]
        var final = frame
        if mode != .noUsage { final["usageMetadata"] = ["promptTokenCount": 1000, "candidatesTokenCount": 100, "thoughtsTokenCount": 100] }
        try receive(Data("data: ".utf8) + JSONSerialization.data(withJSONObject: final) + Data("\n\n".utf8))
    }
}
