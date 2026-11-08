import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct InsightCoordinatorTests {
    @Test func permissionAndActivityGateAllCalls() async {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        ai.resume()
        await ai.ask("What next?")
        #expect(client.requests.isEmpty)
        ai.setPermission(true, after: 0)
        #expect(!ai.automaticEnabled)
        #expect(ai.receive(insightEvent(session: store.sessionID)) == nil)
        await ai.ask("What next?")
        #expect(client.requests.count == 1)
        #expect(ai.insights.first?.text == "A synthetic answer")
        ai.suspend()
        await ai.ask("Do not send")
        #expect(client.requests.count == 1)
        ai.reset()
        #expect(!ai.permitted)
        #expect(!ai.automaticEnabled)
        #expect(ai.insights.isEmpty)
    }

    @Test func revocationBeforeScheduledAutomaticWorkStartsSendsNothing() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let ai = InsightCoordinator(store: store, client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        let operation = try #require(ai.receive(insightEvent(session: store.sessionID)))
        ai.setPermission(false, after: 0)
        await operation.value
        #expect(client.requests.isEmpty)
        #expect(ai.state == .off)
    }

    @Test func revocationRejectsLateUpdatesAndCompletion() async {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let ai = InsightCoordinator(store: store, client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        let operation = Task { await ai.ask("Explain") }
        await gate.entered.next()
        ai.setPermission(false, after: 0)
        gate.release()
        await operation.value
        #expect(ai.insights.first?.status == .interrupted)
        #expect(ai.insights.first?.text != "A synthetic answer")
        #expect(ai.state == .off)
    }

    @Test func manualPreemptsAutomaticWithoutDuplicatingManual() async throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let automaticGate = TestGate()
        client.gate = automaticGate
        let ai = InsightCoordinator(store: store, client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        let auto = try #require(ai.receive(insightEvent(session: store.sessionID)))
        await automaticGate.entered.next()
        let manualGate = TestGate()
        client.gate = manualGate
        let manual = Task { await ai.ask("Manual question") }
        await manualGate.entered.next()
        await ai.ask("Do not duplicate")
        automaticGate.release()
        await auto.value
        manualGate.release()
        await manual.value
        #expect(client.requests.map(\.trigger) == [.automatic, .manual])
        #expect(ai.insights.filter { $0.status == .complete }.count == 1)
        #expect(ai.insights.last?.text == "A synthetic answer")
    }

    @Test func automaticOnlyUsesPostConsentFinalsAndThrottles() async {
        let store = MeetingSessionStore(sessionID: UUID())
        store.receive(insightEvent(session: store.sessionID, text: "Private earlier content", offset: 1))
        let client = FakeInsightClient()
        var now = 100.0
        let ai = InsightCoordinator(store: store, client: client, now: { now })
        ai.resume()
        ai.setPermission(true, after: 10)
        ai.setAutomatic(true, after: 10)
        #expect(ai.receive(insightEvent(session: store.sessionID, offset: 2)) == nil)
        #expect(ai.receive(insightEvent(session: store.sessionID, offset: 11, final: false)) == nil)
        let first = insightEvent(session: store.sessionID, offset: 11)
        await ai.receive(first)?.value
        #expect(client.requests.first?.events == [first])
        #expect(ai.receive(first) == nil)
        #expect(ai.receive(insightEvent(session: store.sessionID, text: "What is next?", offset: 12)) == nil)
        now = 112
        await ai.receive(insightEvent(session: store.sessionID, text: "What is next?", offset: 13))?.value
        now = 125
        #expect(ai.receive(insightEvent(session: store.sessionID, text: "When is the review?", offset: 14)) == nil)
        #expect(client.requests.count == 2)
    }

    @Test func timeoutRejectsAClientThatReturnsAfterCancellation() async {
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: client, timeout: .milliseconds(10))
        ai.resume()
        ai.setPermission(true, after: 0)
        let operation = Task { await ai.ask("Explain") }
        await gate.entered.next()
        await gate.cancelled.next()
        #expect(ai.state == .failed(.timeout))
        gate.release()
        await operation.value
        #expect(ai.state == .failed(.timeout))
        #expect(ai.insights.first?.status == .interrupted)
    }

    @Test func newSessionRejectsOldResponseEvenWhenPermissionIsGrantedAgain() async {
        let store = MeetingSessionStore(sessionID: UUID())
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let ai = InsightCoordinator(store: store, client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        let old = Task { await ai.ask("Old meeting") }
        await gate.entered.next()
        ai.reset()
        store.reset(sessionID: UUID())
        ai.resume()
        ai.setPermission(true, after: 0)
        client.gate = nil
        await ai.ask("New meeting")
        gate.release()
        await old.value
        #expect(ai.insights.count == 1)
        #expect(ai.insights.first?.id == client.requests.last?.id)
    }

    @Test func failureDoesNotExposeRemoteErrorAndAllowsExplicitRetry() async {
        let client = FakeInsightClient()
        client.failure = NSError(domain: "secret request text", code: 1)
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: client)
        ai.resume()
        ai.setPermission(true, after: 0)
        ai.setAutomatic(true, after: 0)
        await ai.ask("Question")
        #expect(ai.state == .failed(.invalidResponse))
        #expect(!ai.automaticEnabled)
        #expect(client.requests.count == 1)
        client.failure = nil
        await ai.ask("Question")
        #expect(client.requests.count == 2)
        #expect(client.requests[0].id != client.requests[1].id)
    }
}

@MainActor
final class FakeInsightClient: InsightClient {
    var requests: [InsightRequest] = []
    var gate: TestGate?
    var failure: (any Error)?

    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        let currentGate = gate
        await currentGate?.wait()
        if let failure { throw failure }
        update("A synthetic answer")
        return InsightResult(kind: .answerSuggestion, text: "A synthetic answer", evidenceIDs: request.events.map(\.id))
    }
}
