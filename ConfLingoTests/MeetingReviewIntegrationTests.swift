import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingReviewIntegrationTests {
    @Test func summaryRequiresEndedMeetingAndNeverRestartsCapture() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let meeting = MeetingWorkspace(controller: fixture.controller(owner: .meeting), insightClient: client,
                                       credentials: GeminiCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("Summary fixture", time: 1)
        await meeting.pause()
        let plan = try meeting.summaryPlan()
        await meeting.generateSummary(plan, consent: true)
        #expect(client.requests.isEmpty)
        await meeting.end()
        await meeting.generateSummary(plan, consent: false)
        #expect(client.requests.isEmpty)
        await meeting.generateSummary(plan, consent: true)
        #expect(client.requests.count == 1)
        #expect(meeting.summary.completed != nil)
        #expect(meeting.phase == .idle)
        #expect(fixture.microphone.starts == 1)
        #expect(!meeting.ai.canAsk)
        #expect(meeting.exportSnapshot != nil)
    }

    @Test func leavingReviewInvalidatesPreparedConsentBeforeTaskStarts() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client,
                                       credentials: GeminiCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        fixture.microphone.finalOnStop = "Synthetic final"
        await meeting.end()
        let plan = try meeting.summaryPlan()
        meeting.cancelSummary()
        await meeting.generateSummary(plan, consent: true)
        #expect(client.requests.isEmpty)
        #expect(meeting.summary.completed == nil)
    }

    @Test func globalAIStopAlsoCancelsReviewSummary() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client,
                                       credentials: GeminiCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        fixture.microphone.finalOnStop = "Synthetic final"
        await meeting.end()
        let gate = TestGate()
        client.gate = gate
        let plan = try meeting.summaryPlan()
        let operation = Task { await meeting.generateSummary(plan, consent: true) }
        await gate.entered.next()
        #expect(meeting.canStopAI)
        #expect(meeting.aiStatus.contains("要約"))
        meeting.setAIAllowed(false)
        gate.release()
        await operation.value
        #expect(meeting.summary.state == .interrupted)
        #expect(meeting.summary.completed == nil)
        #expect(!meeting.canStopAI)
    }

    @Test func keyChangeCancelsSummaryAndDiscardResetsReviewState() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let credentials = GeminiCredentials(store: MemoryAPIKeyStore())
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client, credentials: credentials)
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("Retained fixture", time: 1)
        await meeting.end()
        let gate = TestGate()
        client.gate = gate
        let plan = try meeting.summaryPlan()
        let operation = Task { await meeting.generateSummary(plan, consent: true) }
        await gate.entered.next()
        credentials.save("synthetic-test-key")
        gate.release()
        await operation.value
        #expect(meeting.summary.state == .interrupted)
        #expect(meeting.summary.completed == nil)
        meeting.requestDiscard()
        meeting.showsDiscardConfirmation = false
        meeting.confirmDiscard()
        #expect(meeting.store.finals.count == 1)
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.summary.state == .idle)
        #expect(meeting.candidates.items.isEmpty)
        #expect(meeting.exportSnapshot == nil)
    }
}
