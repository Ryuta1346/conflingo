import Foundation
import Testing
@testable import ConfLingo

extension MixedContextEvaluationCase {
    // Paired controls: explicit relationships and schedules must survive grounding constraints.
    static let groundingControls: [Self] = [
        Self(id: "dependency-unstated", question: "What is known about the audit and deployment?",
             answerLanguage: "en", lines: ["The audit is in progress.", "Can we deploy on Tuesday?"],
             metadataLanguage: "en-US"),
        Self(id: "dependency-explicit", question: "What is known about the audit and deployment?",
             answerLanguage: "en", lines: ["Deployment requires the audit to be complete.", "The audit is in progress."],
             metadataLanguage: "en-US"),
        Self(id: "subject-unstated", question: "What conflicts?", answerLanguage: "en",
             lines: ["Tuesday conflicts with the Monday date previously mentioned."], metadataLanguage: "en-US"),
        Self(id: "subject-explicit", question: "What is the reported workshop date?", answerLanguage: "en",
             lines: ["The workshop date was changed from Monday to Tuesday."], metadataLanguage: "en-US"),
        Self(id: "update-expected", question: "更新情報について分かっていることは？", answerLanguage: "ja",
             lines: ["We expect an update by Tuesday."], metadataLanguage: "en-US"),
        Self(id: "update-scheduled", question: "更新情報について分かっていることは？", answerLanguage: "ja",
             lines: ["The update is scheduled for Tuesday."], metadataLanguage: "en-US")
    ]
}

extension GeminiLiveEvaluationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CONFLINGO_GROUNDING_LIVE_AI"] == "1"))
    func groundingControlsCorpus() async throws {
        let store = KeychainAPIKeyStore()
        let client = GeminiInsightClient(key: { try await store.read() })
        for fixture in MixedContextEvaluationCase.groundingControls {
            let request = try fixture.request()
            let result = try await client.generate(request) { _ in }
            let card = try result.card(for: request)
            #expect(!card.hasInvalidEvidence, "Invalid evidence: \(fixture.id)")
            #expect(fixture.qualityIssues(in: card.text).isEmpty, "Quality screen: \(fixture.id)")
        }
    }
}
