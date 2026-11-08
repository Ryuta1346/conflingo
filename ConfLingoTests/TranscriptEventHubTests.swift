import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct TranscriptEventHubTests {
    @Test func fansOutFinalsInOrderWithoutWaitingForSlowSubscriber() async throws {
        let hub = TranscriptEventHub(finalCapacity: 2)
        let fast = await hub.subscribe()
        let slow = await hub.subscribe()
        let first = transcriptEvent(sessionID: UUID(), text: "First")
        let second = transcriptEvent(sessionID: first.sessionID, text: "Second")
        _ = try await hub.publish(first)
        #expect(try await fast.next() == first)
        _ = try await hub.publish(second)
        #expect(try await fast.next() == second)
        await hub.finish()
        #expect(try await slow.next() == first)
        #expect(try await slow.next() == second)
        #expect(try await slow.next() == nil)
        #expect(try await fast.next() == nil)
    }

    @Test func partialFloodKeepsFinalAndLatestPartialPerOrigin() async throws {
        let hub = TranscriptEventHub(finalCapacity: 1)
        let subscription = await hub.subscribe()
        let final = transcriptEvent(sessionID: UUID())
        _ = try await hub.publish(final)
        for revision in 1...100 {
            _ = try await hub.publish(transcriptEvent(
                sessionID: final.sessionID, text: "partial \(revision)", isFinal: false, revision: revision
            ))
        }
        _ = try await hub.publish(transcriptEvent(
            sessionID: final.sessionID, origin: .systemAudio, text: "remote", isFinal: false
        ))
        await hub.finish()
        #expect(try await subscription.next() == final)
        #expect(try await subscription.next()?.text == "partial 100")
        #expect(try await subscription.next()?.text == "remote")
        #expect(try await subscription.next() == nil)
    }

    @Test func overflowIsReportedToProducerAndSlowConsumerOnly() async throws {
        let hub = TranscriptEventHub(finalCapacity: 1)
        let fast = await hub.subscribe()
        let slow = await hub.subscribe()
        let first = transcriptEvent(sessionID: UUID())
        _ = try await hub.publish(first)
        _ = try await fast.next()
        let second = transcriptEvent(sessionID: first.sessionID, text: "Second")
        let failures = try await hub.publish(second)
        #expect(failures == [slow.id])
        #expect(try await fast.next() == second)
        #expect(try await slow.next() == first)
        await #expect(throws: TranscriptEventHub.Failure.overflow) { try await slow.next() }
        let third = transcriptEvent(sessionID: first.sessionID, text: "Third")
        #expect(try await hub.publish(third).isEmpty)
        #expect(try await fast.next() == third)
        await hub.finish()
    }

    @Test func finalReplacesQueuedPartialOfSameOrigin() async throws {
        let hub = TranscriptEventHub()
        let subscription = await hub.subscribe()
        let sessionID = UUID()
        let id = UUID()
        _ = try await hub.publish(transcriptEvent(id: id, sessionID: sessionID, isFinal: false))
        let final = transcriptEvent(id: id, sessionID: sessionID, revision: 2)
        _ = try await hub.publish(final)
        await hub.finish()
        #expect(try await subscription.next() == final)
        #expect(try await subscription.next() == nil)
    }

    @Test func cancellationAndFinishReleaseReaders() async throws {
        let hub = TranscriptEventHub()
        let canceled = await hub.subscribe()
        let finished = await hub.subscribe()
        let reader = Task { try await canceled.next() }
        await canceled.cancel()
        #expect(try await reader.value == nil)
        await hub.finish()
        #expect(try await finished.next() == nil)
        let late = await hub.subscribe()
        #expect(try await late.next() == nil)
        await #expect(throws: TranscriptEventHub.Failure.closed) {
            try await hub.publish(transcriptEvent(sessionID: UUID()))
        }
    }

    @Test func canceledTaskDoesNotLeaveSubscriberWaiting() async throws {
        let hub = TranscriptEventHub()
        let subscription = await hub.subscribe()
        let reader = Task { try await subscription.next() }
        reader.cancel()
        #expect(try await reader.value == nil)
        #expect(try await subscription.next() == nil)
        await hub.finish()
    }
}
