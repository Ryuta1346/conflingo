import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized)
    struct DR4ConferenceViewTests {
        @Test(arguments: [false, true])
        func documentAnswersWarnOnlyWhenCitationsAreMissing(citesMaterials: Bool) async throws {
            let workspace = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: conferenceTestSettings(),
                client: DR4DocumentAnswerClient(citesMaterials: citesMaterials))
            await workspace.knowledge.add(data: Data("料金は100円です。".utf8), filename: "price.md")
            workspace.setQuestionPermission(true)
            await workspace.ask("料金")
            let answer = try #require(workspace.answers.first)
            #expect(answer.knowledgeReferences.isEmpty == !citesMaterials)
            let fixture = DR3Host(ConferenceAssistanceView(workspace: workspace), height: 900)
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.strings.contains("資料根拠なし・要確認") == !citesMaterials)
        }

        @Test func documentSheetContainsOnlyMaterialsAndTerms() async throws {
            let composition = AppComposition(arguments: ["--ui-preview"])
            let fixture = DR3Host(ConferenceKnowledgeView(workspace: composition.conferenceKnowledge,
                library: composition.library, fontSize: 16,
                sourceLanguage: "en-US", targetLanguage: nil, applyTerms: {}), height: 1500)
            defer { fixture.close() }
            await fixture.layout()
            #expect(!fixture.strings.contains("資料だけに質問"))
            #expect(fixture.element("このMacに保存") == nil)
            #expect(fixture.element("質問する") == nil)
            #expect(fixture.element("LLM設定") == nil)
        }

        @Test func sharedSettingsKeepManualAndAutomaticConsentSeparate() async throws {
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            let fixture = DR3Host(MeetingAISettings(meeting: meeting), height: 1800)
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.element("手動質問にも資料を使う") != nil)
            #expect(!meeting.ai.permitted)
            #expect(!meeting.knowledge.permitted)
            #expect(!meeting.ai.automaticEnabled)
        }
    }
}

private struct DR4DocumentAnswerClient: InsightClient {
    let citesMaterials: Bool
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        InsightResult(kind: .answerSuggestion, text: "100円です", evidenceIDs: [],
            knowledgeIDs: citesMaterials ? request.knowledge.map(\.id) : [])
    }
}
