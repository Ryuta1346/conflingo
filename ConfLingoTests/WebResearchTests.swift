import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WebResearchTests {
    @Test func permissionAndContextUseOneLLMOperation() async throws {
        let fixture = ResearchFixture()
        let id = UUID()
        fixture.store.receive(TranscriptEvent(id: id, sessionID: fixture.store.sessionID, origin: .systemAudio,
            languageCode: "en", startOffset: 1, endOffset: 2, text: "price?", isFinal: true, revision: 1, sourceStartTime: 1))
        await fixture.knowledge.add(data: Data("price 100".utf8), filename: "price.md")
        await fixture.research.run(question: "price?", language: .english)
        #expect(fixture.client.requests.isEmpty)
        fixture.research.setPermission(true)
        await fixture.research.run(question: "price?", language: .english)
        let request = try #require(fixture.client.requests.first)
        #expect(request.events.map(\.id) == [id])
        #expect(request.knowledge.count == 1)
        #expect(fixture.client.requests.count == 1)
        #expect(fixture.research.answers.first?.webReferences?.count == 1)
    }

    @Test func selectedOlderSpeechIsUsedInsteadOfRecentConversation() async throws {
        let fixture = ResearchFixture()
        let selected = UUID()
        for index in 0..<40 {
            fixture.store.receive(TranscriptEvent(id: index == 0 ? selected : UUID(), sessionID: fixture.store.sessionID,
                origin: .microphone, languageCode: "en", startOffset: Double(index), endOffset: Double(index + 1),
                text: index == 0 ? "Original question" : "Unrelated newer topic", isFinal: true, revision: 1, sourceStartTime: Double(index)))
        }
        fixture.research.open("Original question", evidenceIDs: [selected])
        fixture.research.setPermission(true)
        await fixture.research.run(question: "Explain this", language: .english)
        #expect(fixture.client.requests.first?.events.map(\.id) == [selected])
        fixture.research.open("General question")
        #expect(fixture.research.contextEvents.count == 40)
    }

    @Test(arguments: ["", String(repeating: "x", count: 2_001)])
    func invalidQuestionDoesNotSend(question: String) async {
        let fixture = ResearchFixture()
        fixture.research.setPermission(true)
        await fixture.research.run(question: question, language: .english)
        #expect(fixture.client.requests.isEmpty)
        #expect(fixture.research.requestCount == 0)
    }

    @Test(arguments: ["cancel", "permission", "model", "documents", "key", "reset", "caller"])
    func invalidationRejectsLateAnswers(action: String) async throws {
        let fixture = ResearchFixture()
        let gate = TestGate()
        fixture.client.gate = gate
        fixture.research.setPermission(true)
        let task = Task { await fixture.research.run(question: "topic", language: .english) }
        await gate.entered.next()
        switch action {
        case "permission": fixture.research.setPermission(false)
        case "model":
            var value = fixture.settings.selected
            value.model = "different"
            try fixture.settings.save(value)
        case "documents": await fixture.knowledge.add(data: Data("changed".utf8), filename: "new.md")
        case "key": _ = fixture.settings.credentials.save("different")
        case "reset": fixture.research.reset()
        case "caller": task.cancel()
        default: fixture.research.cancel()
        }
        gate.release()
        await task.value
        #expect(fixture.research.answers.isEmpty)
        #expect(!fixture.research.isBusy)
        #expect(fixture.research.requestCount == (action == "reset" ? 0 : 1))
    }

    @Test func deadlineRejectsLateResponse() async {
        let fixture = ResearchFixture()
        let gate = TestGate()
        fixture.client.gate = gate
        let research = WebResearchCoordinator(store: fixture.store, knowledge: fixture.knowledge, settings: fixture.settings,
            client: fixture.client, timeout: .milliseconds(5))
        research.setPermission(true)
        let task = Task { await research.run(question: "topic", language: .english) }
        await gate.entered.next()
        await gate.cancelled.next()
        gate.release()
        await task.value
        #expect(research.status.contains("タイムアウト"))
        #expect(research.answers.isEmpty)
    }

    @Test func noSourcesIsFailureAndLimitDoesNotRetry() async {
        let fixture = ResearchFixture()
        fixture.client.failure = ResearchFailure.noSources
        fixture.research.limit = 1
        fixture.research.setPermission(true)
        await fixture.research.run(question: "topic", language: .english)
        await fixture.research.run(question: "topic", language: .english)
        #expect(fixture.research.answers.isEmpty)
        #expect(fixture.client.requests.count == 1)
        #expect(fixture.research.status.contains("出典"))
    }

    @Test func unsupportedConnectionDoesNotSend() async throws {
        let fixture = ResearchFixture()
        var local = LLMConnection.preset(.local)
        local.model = "test"
        try fixture.settings.save(local)
        fixture.research.setPermission(true)
        await fixture.research.run(question: "topic", language: .english)
        #expect(!fixture.research.supported)
        #expect(fixture.research.status.contains("未対応"))
        #expect(fixture.client.requests.isEmpty)
    }
}

@MainActor final class ResearchClient: LLMWebResearching {
    var requests: [InsightRequest] = []
    var gate: TestGate?
    var failure: (any Error)?
    func generate(_ request: InsightRequest) async throws -> MeetingInsight {
        requests.append(request)
        await gate?.wait()
        if let failure { throw failure }
        let reference = WebReference(id: UUID(), url: URL(string: "https://example.com/source")!, title: "Public source", fetchedAt: Date())
        return MeetingInsight(id: request.id, kind: .answerSuggestion, text: "Combined answer [[web:\(reference.id)]]", priority: 1,
            evidenceIDs: request.events.map(\.id), knowledgeReferences: request.knowledge, webReferences: [reference])
    }
}

@MainActor final class ResearchFixture {
    let store = MeetingSessionStore(sessionID: UUID())
    let knowledge = KnowledgeStore()
    let settings = conferenceTestSettings()
    let client = ResearchClient()
    lazy var research = WebResearchCoordinator(store: store, knowledge: knowledge, settings: settings, client: client)
}
