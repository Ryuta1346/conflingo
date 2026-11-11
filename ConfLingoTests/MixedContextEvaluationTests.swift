import Foundation
import Testing
@testable import ConfLingo

struct MixedContextEvaluationTests {
    @Test func englishAnswerToJapaneseQuestionFailsLanguageCheck() {
        let sample = MixedContextEvaluationCase.all[0]
        #expect(sample.qualityIssues(in: "The review is still in progress.").contains("language"))
    }

    @Test(arguments: ["開始できるかは未定です。", "開始は未決定です。", "開催日は決まっていません。"])
    func unknownFeasibilityCannotBecomeUndecided(text: String) {
        #expect(MixedContextEvaluationCase.all[1].qualityIssues(in: text).contains("unsupportedDecisionStatus"))
    }

    @Test func unknownAndExplicitlyUndecidedRemainDifferent() {
        #expect(MixedContextEvaluationCase.all[1].qualityIssues(in: "開始できるかは不明です。確認が必要です。").isEmpty)
        #expect(MixedContextEvaluationCase.all[3].qualityIssues(in: "It is unknown whether the pilot can start.").isEmpty)
        #expect(MixedContextEvaluationCase.all[6].qualityIssues(in: "開催日は未定です。来週相談すると述べています。").isEmpty)
        #expect(MixedContextEvaluationCase.all[7].qualityIssues(in: "The workshop date has not been decided yet.").isEmpty)
    }

    @Test(arguments: ["It is undecided.", "The start date is not set.", "The start date hasn't been decided."])
    func englishUnknownCannotBecomeUndecided(text: String) {
        #expect(MixedContextEvaluationCase.all[3].qualityIssues(in: text).contains("unsupportedDecisionStatus"))
    }
}

extension GeminiLiveEvaluationTests {
    @Test(.enabled(if: RAGLiveConfiguration.legacyEnabled("CONFLINGO_LIVE_AI")))
    func mixedContextCorpus() async throws {
        let store = KeychainAPIKeyStore()
        let client = GeminiInsightClient(key: { try await store.read() })
        var measurements: [[String: Any]] = []
        for round in 1...3 {
            for sample in MixedContextEvaluationCase.all {
                let request = try sample.request()
                let started = ProcessInfo.processInfo.systemUptime
                let result = try await client.generate(request) { _ in }
                let card = try result.card(for: request)
                let issues = sample.qualityIssues(in: card.text)
                #expect(!card.hasInvalidEvidence, "Invalid evidence: \(sample.id)")
                #expect(issues.isEmpty, "Quality checks: \(sample.id), \(issues)")
                var row: [String: Any] = ["case": sample.id, "round": round,
                                         "seconds": ProcessInfo.processInfo.systemUptime - started,
                                         "issues": issues, "invalidEvidence": card.hasInvalidEvidence]
                if let usage = result.usage {
                    row["inputTokens"] = usage.inputTokens
                    row["outputTokens"] = usage.outputTokens
                    row["thinkingTokens"] = usage.thinkingTokens
                }
                measurements.append(row)
                let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: FileManager.default.temporaryDirectory
                    .appendingPathComponent("conflingo-pr6-mixed-evaluation.json"), options: .atomic)
            }
        }
    }
}
