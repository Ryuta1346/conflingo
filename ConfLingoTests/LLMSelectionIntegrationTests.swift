import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMSelectionIntegrationTests {
    @Test func changingConnectionCancelsPendingWorkAndSummaryConfirmation() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let settings = LLMSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: TestConnectionKeys().store)
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client, llmSettings: settings)
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        let ask = Task { await meeting.ai.ask("Explain") }
        await gate.entered.next()
        var local = LLMConnection.preset(.local)
        local.model = "qwen-installed"
        try settings.save(local)
        #expect(!meeting.ai.permitted)
        #expect(!meeting.ai.automaticEnabled)
        gate.release()
        await ask.value
        #expect(meeting.insights.allSatisfy { $0.status != .complete })
        await meeting.end()
    }
}

@MainActor
struct LLMSelectionRaceTests {
    @Test func configurationChangedDuringKeyReadNeverReachesHTTP() async throws {
        let store = SuspendedLLMKeyStore()
        let settings = LLMSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: { _ in store })
        var first = LLMConnection.preset(.custom)
        first.baseURL = "https://first.example/v1"
        first.model = "model"
        try settings.save(first)
        let http = FakeInsightHTTP()
        let client = SelectedLLMClient(settings: settings, transport: http)
        let request = try InsightRequest(sessionID: UUID(), question: "Question", trigger: .manual, events: [])
        let operation = Task { try await client.generate(request) { _ in Issue.record("No stale updates") } }
        await store.gate.entered.next()
        settings.select(LLMConnection.legacyGeminiID)
        store.gate.release()
        do { _ = try await operation.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
        #expect(http.requests.isEmpty)
    }

    @Test func switchingModelInvalidatesSummaryConfirmation() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let settings = LLMSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: TestConnectionKeys().store)
        let meeting = MeetingWorkspace(controller: fixture.controller(owner: .meeting), insightClient: client, llmSettings: settings)
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("Synthetic summary", time: 1)
        await meeting.end()
        let plan = try meeting.summaryPlan()
        var updated = settings.selected
        updated.model = "another-model"
        try settings.save(updated)
        #expect(!meeting.isSummaryPlanCurrent(plan))
        await meeting.generateSummary(plan, consent: true)
        #expect(client.requests.isEmpty)
    }
}

@MainActor
private final class SuspendedLLMKeyStore: APIKeyStore {
    let gate = TestGate()
    func read() async throws -> String? { await gate.wait(); return "old-key" }
    func save(_ key: String) throws {}
    func delete() throws {}
}
