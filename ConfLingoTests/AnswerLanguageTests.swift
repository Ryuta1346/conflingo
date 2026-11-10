import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AnswerLanguageTests {
    @Test func selectionPersistsIndependentlyOfSpeechAndTranslation() throws {
        let suite = "AnswerLanguageTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("en-US", forKey: "sourceLocaleID")
        defaults.set("ja", forKey: "targetLanguageID")
        defaults.set("unknown", forKey: "aiAnswerLanguage")
        let first = MeetingWorkspace(controller: DualFixture().controller(), defaults: defaults)
        #expect(first.answerLanguage == .japanese)
        first.answerLanguage = .english
        let restored = MeetingWorkspace(controller: DualFixture().controller(), defaults: defaults)
        #expect(restored.answerLanguage == .english)
        #expect(restored.ai.answerLanguage == .english)
        #expect(defaults.string(forKey: "sourceLocaleID") == "en-US")
        #expect(defaults.string(forKey: "targetLanguageID") == "ja")
        restored.answerLanguage = .japanese
        #expect(defaults.string(forKey: "aiAnswerLanguage") == "ja")
    }

    @Test func manualAndAutomaticCaptureLanguageAtRequestCreation() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let ai = InsightCoordinator(store: store, client: client)
        ai.answerLanguage = .english
        ai.resume()
        ai.setPermission(true, after: 0)
        let manual = Task { await ai.ask("料金はいくらですか？") }
        await gate.entered.next()
        ai.answerLanguage = .japanese
        #expect(client.requests.first?.answerLanguage == .english)
        gate.release()
        await manual.value
        client.gate = nil
        ai.setAutomatic(true, after: 0)
        let automatic = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await automatic.value
        #expect(client.requests.map(\.answerLanguage) == [.english, .japanese])
        #expect(client.requests.map(\.trigger) == [.manual, .automatic])
        #expect(ai.insights.first?.text == "A synthetic answer")
    }

    @Test(arguments: AnswerLanguage.allCases)
    func explicitLanguageReachesHTTPWithoutChangingQuestion(language: AnswerLanguage) async throws {
        let question = language == .english ? "料金はいくらですか？" : "What is the price?"
        let request = try InsightRequest(sessionID: UUID(), question: question, trigger: .manual,
                                        events: [], answerLanguage: language)
        let transport = FakeInsightHTTP()
        transport.chunks = [try geminiSSE(payload: "{\"text\":\"Synthetic\",\"kind\":\"answerSuggestion\",\"evidenceIDs\":[]}")]
        _ = try await GeminiInsightClient(key: { "synthetic-key" }, transport: transport).generate(request) { _ in }
        let data = try #require(transport.requests.first?.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let contents = try #require(body["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: String]])
        let payload = try #require(parts.last?["text"])
        let last = try #require(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: String])
        #expect(last["question"] == question)
        #expect(last["answerLanguage"] == language.rawValue)
    }
}
