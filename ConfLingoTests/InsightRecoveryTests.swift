import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InsightRecoveryTests {
    @Test func startupFinalIsSentOnceOnlyAfterActivation() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        await ai.attach(to: TranscriptEventHub())
        let event = insightEvent(session: store.sessionID)
        store.receive(event)
        ai.receive(event)
        #expect(client.requests.isEmpty)
        ai.resume()
        try #require(await eventually { client.requests.count == 1 && ai.state == .ready })
        #expect(client.requests.first?.events == [event])
        #expect(ai.receive(event) == nil)
        #expect(client.requests.count == 1)
        ai.suspend()
    }

    @Test(arguments: ["stop", "permission", "automatic", "reset"])
    func cancelledStartupNeverReplaysBufferedSpeech(action: String) async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        await ai.attach(to: TranscriptEventHub())
        let old = insightEvent(session: store.sessionID, text: "Old question?")
        ai.receive(old)
        switch action {
        case "stop": ai.suspend()
        case "permission": ai.setPermission(false, after: 0)
        case "automatic": ai.setAutomatic(false, after: 0)
        default: ai.reset()
        }
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        if action == "stop" || action == "reset" { await ai.attach(to: TranscriptEventHub()) }
        ai.resume()
        let fresh = insightEvent(session: store.sessionID, text: "Fresh question?", offset: 2)
        await ai.receive(fresh)?.value
        try #require(client.requests.count == 1)
        #expect(client.requests.first?.events == [fresh])
        ai.suspend()
    }

    @Test func startupIgnoresIneligibleAndOversizedSpeech() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        ai.setPermission(true, after: 10)
        ai.setAutomatic(true, after: 10)
        await ai.attach(to: TranscriptEventHub())
        let valid = insightEvent(session: store.sessionID, offset: 11)
        ai.receive(valid)
        ai.receive(insightEvent(session: UUID(), offset: 12))
        ai.receive(insightEvent(session: store.sessionID, offset: 9))
        ai.receive(insightEvent(session: store.sessionID, offset: 13, final: false))
        ai.receive(insightEvent(session: store.sessionID, text: String(repeating: "?", count: 12_001), offset: 14))
        ai.resume()
        try #require(await eventually { client.requests.count == 1 })
        #expect(client.requests.first?.events == [valid])
        ai.suspend()
    }

    @Test func overflowCannotBeHiddenByReenablingOrManualSuccessAndReconnectRecovers() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        let hub = TranscriptEventHub(finalCapacity: 1)
        await ai.attach(to: hub)
        ai.resume()
        ai.setPermission(true, after: 0)
        try await hub.publishBurst((0..<5).map { insightEvent(session: store.sessionID, text: "plain \($0)") })
        try #require(await eventually { ai.state == .failed(.queueOverflow) })
        ai.setAutomatic(true, after: 0)
        #expect(!ai.automaticEnabled)
        #expect(ai.statusText.contains("一時停止"))
        ai.setPermission(false, after: 0)
        ai.setPermission(true, after: 0)
        await ai.ask("Manual still works?")
        ai.setAutomatic(true, after: 0)
        #expect(!ai.automaticEnabled)
        #expect(ai.statusText.contains("一時停止"))
        #expect(client.requests.count == 1)
        ai.suspend()
        let replacement = TranscriptEventHub()
        await ai.attach(to: replacement)
        ai.resume()
        #expect(!ai.automaticEnabled)
        ai.setAutomatic(true, after: 0)
        #expect(ai.automaticEnabled)
        let fresh = insightEvent(session: store.sessionID, offset: 10)
        try await replacement.publish(fresh)
        try #require(await eventually { client.requests.count == 2 })
        #expect(client.requests.last?.events == [fresh])
        ai.suspend()
    }

    @Test(arguments: [false, true])
    func firstInputFinalSurvivesDelayedSecondInputUnlessStartupFails(fails: Bool) async throws {
        let fixture = DualFixture()
        let client = FakeInsightClient()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client,
                                       credentials: GeminiCredentials(store: MemoryAPIKeyStore()))
        let gate = TestGate()
        fixture.system.startGate = gate
        fixture.system.startError = fails ? .start : nil
        meeting.consentConfirmed = true
        meeting.setAIAllowed(true)
        meeting.setAutomaticAI(true)
        let start = Task { await meeting.start() }
        await gate.entered.next()
        try await fixture.microphone.emit("Can we launch?", time: 1)
        try #require(await eventually { meeting.store.finals.count == 1 })
        #expect(client.requests.isEmpty)
        gate.release()
        await start.value
        if fails {
            #expect(client.requests.isEmpty)
            fixture.system.startGate = nil
            fixture.system.startError = nil
            await meeting.start()
            #expect(meeting.ai.insights.isEmpty)
        } else {
            try #require(await eventually { client.requests.count == 1 })
            #expect(client.requests.first?.events.first?.text == "Can we launch?")
        }
        await meeting.end()
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < end {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return condition()
    }
}

private extension TranscriptEventHub {
    func publishBurst(_ events: [TranscriptEvent]) throws {
        for event in events { try publish(event) }
    }
}
