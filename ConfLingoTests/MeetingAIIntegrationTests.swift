import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingAIIntegrationTests {
    @Test func pauseDoesNotWaitForAIAndResumeReconnects() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client,
                                       credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        meeting.setAutomaticAI(true)
        try await fixture.system.emit("Can we proceed?", time: 2)
        await gate.entered.next()
        fixture.microphone.finalOnStop = "What about the last question?"
        await meeting.pause()
        #expect(meeting.phase == .idle)
        #expect(meeting.ai.state == .paused)
        #expect(client.requests.count == 1)
        #expect(meeting.store.finals.count == 2)
        gate.release()
        client.gate = nil
        await meeting.start()
        await meeting.ai.ask("What was discussed?")
        #expect(client.requests.count == 2)
        #expect(client.requests.last?.events.count == 2)
        #expect(meeting.insights.filter { $0.status == .complete }.count == 1)
        await meeting.end()
    }

    @Test func inputFailureAndKeyReplacementRevokeInFlightWork() async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let settings = APIKeyCredentials(store: MemoryAPIKeyStore())
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client, credentials: settings)
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        let ask = Task { await meeting.ai.ask("Explain") }
        await gate.entered.next()
        fixture.system.fail(DualFakeSpeech.Failure.recognition)
        #expect(meeting.ai.state == .paused)
        gate.release()
        await ask.value
        await meeting.controller.stop()
        #expect(meeting.insights.first?.status == .interrupted)
        settings.save("replacement-key")
        #expect(!meeting.ai.permitted)
        #expect(meeting.ai.state == .off)
    }

    @Test func overflowOfOptionalSubscriberDoesNotStopTranscription() async throws {
        let fixture = DualFixture()
        let controller = fixture.controller()
        var optional: TranscriptEventHub.Subscription?
        controller.prepareOptionalConsumer = { hub in optional = await hub.subscribe() }
        await controller.start()
        for index in 0..<270 {
            try await fixture.microphone.emit("line \(index)", time: Double(index))
        }
        #expect(controller.phase == .listening)
        await controller.stop()
        #expect(controller.store.finals.count == 270)
        let subscription = try #require(optional)
        do {
            while try await subscription.next() != nil {}
            Issue.record("Expected optional subscriber overflow")
        } catch { #expect(error as? TranscriptEventHub.Failure == .overflow) }
    }

    @Test func discardedSessionClearsAIConsentAndResults() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: FakeInsightClient(),
                                       credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        meeting.setAutomaticAI(true)
        await meeting.ai.ask("Explain")
        await meeting.end()
        meeting.requestDiscard()
        if meeting.showsDiscardConfirmation { meeting.confirmDiscard() }
        #expect(!meeting.ai.permitted)
        #expect(!meeting.ai.automaticEnabled)
        #expect(meeting.insights.isEmpty)
    }
}
