import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ConferenceKnowledgeTests {
    @Test func questionsRequirePermissionAndNeverIncludeCaptions() async throws {
        let client = KnowledgeClient()
        let store = SessionStore()
        _ = store.appendFinal("非公開の字幕", startTime: 1)
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金100円です".utf8), filename: "price.md")
        await workspace.ask("料金は？")
        #expect(client.requests.isEmpty)
        workspace.setQuestionPermission(true)
        await workspace.ask("料金は？")
        let request = try #require(client.requests.first)
        #expect(request.events.isEmpty)
        #expect(request.purpose == .documentQuestion)
        #expect(request.knowledge.count == 1)
        #expect(workspace.answers.first?.knowledgeReferences.count == 1)
    }

    @Test(arguments: ["stop", "documents", "connection", "permission", "reset", "terms"])
    func changesCancelDelayedAnswers(action: String) async throws {
        let client = KnowledgeClient()
        let gate = TestGate()
        client.gate = gate
        let settings = conferenceTestSettings()
        let workspace = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: settings, client: client)
        await workspace.knowledge.add(data: Data("料金100円".utf8), filename: "a.md")
        workspace.setQuestionPermission(true)
        let task = Task { await workspace.ask("料金") }
        await gate.entered.next()
        switch action {
        case "documents": await workspace.knowledge.add(data: Data("別の資料".utf8), filename: "b.md")
        case "connection":
            var connection = settings.selected
            connection.model = "changed-model"
            try settings.save(connection)
        case "permission": workspace.setQuestionPermission(false)
        case "reset": workspace.reset()
        case "terms": workspace.terms.reset()
        default: workspace.stop()
        }
        gate.release()
        await task.value
        #expect(workspace.answers.isEmpty)
        #expect(!workspace.isGenerating)
    }

    @Test func conferenceAllowsImportWhileListeningAndResetIsIndependent() async throws {
        let store = SessionStore()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: KnowledgeClient())
        store.phase = .listening
        #expect(workspace.canEditKnowledge)
        await workspace.knowledge.add(data: Data("会議資料".utf8), filename: "a.md")
        #expect(store.phase == .listening)
        workspace.stop()
        #expect(workspace.knowledge.documents.count == 1)
        workspace.reset()
        #expect(workspace.knowledge.documents.isEmpty)
    }

    @Test func cancellingCallerClearsBusyAndRejectsLateResult() async {
        let client = KnowledgeClient()
        let gate = TestGate()
        client.gate = gate
        let workspace = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金100円".utf8), filename: "a.md")
        workspace.setQuestionPermission(true)
        let task = Task { await workspace.ask("料金") }
        await gate.entered.next()
        task.cancel()
        gate.release()
        await task.value
        #expect(!workspace.isGenerating)
        #expect(workspace.answers.isEmpty)
    }
}

@MainActor
func conferenceTestSettings() -> LLMSettings {
    let defaults = UserDefaults(suiteName: "ConferenceTests-\(UUID())") ?? .standard
    return LLMSettings(defaults: defaults, legacyCredentials: APIKeyCredentials(store: MemoryAPIKeyStore()),
                       keyStore: { _ in MemoryAPIKeyStore() })
}
