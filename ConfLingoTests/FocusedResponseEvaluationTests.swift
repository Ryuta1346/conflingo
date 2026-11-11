import Foundation
import Testing
@testable import ConfLingo

struct FocusedResponseEvaluationTests {
    @Test(arguments: [
        (0, "レビューは進行中です。パイロットの開始可否は不明です。"),
        (1, "The review is in progress. The PILOT may launch Friday."),
        (2, "水曜日に更新情報が得られる見込みです。"),
        (3, "水曜日までに更新情報が得られる見込みです。"),
        (4, "An update is expected on Wednesday."),
        (5, "An update is expected no later than Wednesday.")
    ])
    func flagsCaseSpecificScopeAndTemporalDrift(index: Int, answer: String) {
        #expect(FocusedResponseEvaluationCase.all[index].qualityIssues(in: answer).contains("unsupportedDetail"))
    }

    @Test(arguments: [
        (0, "レビューは現在進行中で、完了していません。"),
        (1, "No, the review is still in progress."),
        (2, "更新情報は水曜までには得られる見込みです。"),
        (3, "水曜日の更新が見込まれます。"),
        (4, "An update is expected no later than Wednesday."),
        (5, "An update is expected on Wednesday.")
    ])
    func acceptsEquivalentSupportedPhrasing(index: Int, answer: String) {
        #expect(FocusedResponseEvaluationCase.all[index].qualityIssues(in: answer).isEmpty)
    }

    @Test func longQuestionStillChecksLanguageAndUnknownStatus() {
        let sample = FocusedResponseEvaluationCase.all[6]
        #expect(sample.qualityIssues(in: "The review is still in progress.").contains("language"))
        #expect(sample.qualityIssues(in: "パイロット開始日は未定です。").contains("unsupportedDecisionStatus"))
    }
}

extension GeminiLiveEvaluationTests {
    @Test(.enabled(if: RAGLiveConfiguration.legacyEnabled("CONFLINGO_FOCUSED_LIVE_AI")))
    func focusedResponseCorpus() async throws {
        let store = KeychainAPIKeyStore()
        let client = GeminiInsightClient(key: { try await store.read() })
        for _ in 1...3 {
            for fixture in FocusedResponseEvaluationCase.all {
                let request = try fixture.sample.request()
                let result = try await client.generate(request) { _ in }
                let card = try result.card(for: request)
                #expect(!card.hasInvalidEvidence, "Invalid evidence: \(fixture.id)")
                #expect(fixture.qualityIssues(in: card.text).isEmpty, "Quality screen: \(fixture.id)")
            }
        }
    }
}
