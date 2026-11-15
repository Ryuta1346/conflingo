import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct DR4PermissionTests {
    @Test func documentQuestionConsentDoesNotGrantTranscriptQuestionMaterialConsent() async throws {
        let client = KnowledgeClient()
        let store = SessionStore()
        _ = store.appendFinal("この発話は資料質問に送りません")
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金は100円です。".utf8), filename: "price.md")
        workspace.setQuestionPermission(true)
        #expect(!workspace.knowledge.permitted)
        #expect(!workspace.assistance.permitted)
        await workspace.ask("料金")
        let request = try #require(client.requests.first)
        #expect(request.events.isEmpty)
        #expect(!request.knowledge.isEmpty)
        workspace.knowledge.setPermission(true)
        workspace.setQuestionPermission(false)
        #expect(workspace.knowledge.permitted)
        #expect(!workspace.questionPermitted)
    }
}

extension DR4PermissionTests {
    @Test func switchingQuestionTargetKeepsDraftsAndUsesTheSelectedRequestContract() async throws {
        let client = KnowledgeClient()
        let store = SessionStore()
        _ = store.appendFinal("非公開の発話")
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金は100円です。".utf8), filename: "price.md")
        workspace.questionDraft = "会話の質問"
        workspace.questionTarget = .documents
        workspace.questionDraft = "料金は？"
        workspace.setQuestionPermission(true)
        await workspace.submitQuestion()
        #expect(client.requests.count == 1)
        #expect(client.requests[0].events.isEmpty)
        #expect(client.requests[0].purpose == .documentQuestion)
        #expect(workspace.answers.count == 1)
        workspace.questionTarget = .conversation
        #expect(workspace.questionDraft == "会話の質問")
        #expect(!workspace.canSubmitQuestion)
        workspace.questionTarget = .documents
        #expect(workspace.questionDraft == "料金は？")
        workspace.reset()
        #expect(workspace.documentDraft.isEmpty && workspace.assistanceDraft.isEmpty)
    }
}
