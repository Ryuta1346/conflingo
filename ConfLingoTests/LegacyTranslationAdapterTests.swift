import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LegacyTranslationAdapterTests {
    @Test func partialUpdatesAndFinalsPreserveSentenceBufferingAndSourceTime() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let session = UUID()
        let adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator)
        let id = UUID()
        adapter.receive(transcriptEvent(id: id, sessionID: session, text: "Hello", isFinal: false))
        #expect(store.volatileText == "Hello")
        #expect(store.units.isEmpty)
        adapter.receive(transcriptEvent(id: id, sessionID: session, text: "Hello", revision: 2))
        #expect(store.units.isEmpty)
        adapter.receive(transcriptEvent(sessionID: session, text: "world."))
        #expect(store.units.map(\.english) == ["Hello world."])
        #expect(store.units.first?.startTime == 2)
        #expect(store.volatileText.isEmpty)
        await adapter.finish()
    }

    @Test func rejectsStaleDuplicateAndForeignEvents() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let session = UUID()
        let adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator)
        let final = transcriptEvent(sessionID: session, text: "Hello.", revision: 3)
        adapter.receive(final)
        adapter.receive(final)
        adapter.receive(transcriptEvent(id: final.id, sessionID: session, text: "old", isFinal: false))
        adapter.receive(transcriptEvent(id: final.id, sessionID: session, text: "late partial", isFinal: false, revision: 4))
        adapter.receive(transcriptEvent(id: final.id, sessionID: session, text: "late final", revision: 5))
        adapter.receive(transcriptEvent(sessionID: UUID(), text: "foreign."))
        adapter.receive(transcriptEvent(sessionID: session, origin: .systemAudio, text: "remote."))
        adapter.receive(transcriptEvent(sessionID: session, text: "  "))
        #expect(store.units.map(\.english) == ["Hello."])
        #expect(store.volatileText.isEmpty)
        await adapter.finish()
    }

    @Test func timeoutFlushesWithoutWaitingForRealTime() async throws {
        let delay = ControlledTranslationDelay()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        var translated = coordinator.attach().makeAsyncIterator()
        let session = UUID()
        let adapter = LegacyTranslationAdapter(
            sessionID: session, store: store, coordinator: coordinator, sleep: delay.sleep
        )
        adapter.receive(transcriptEvent(sessionID: session, text: "unfinished"))
        var requested = delay.requests.makeAsyncIterator()
        let duration = await requested.next()
        #expect(duration == .seconds(4))
        delay.fire()
        let next = await translated.next()
        let item = try #require(next)
        #expect(item.text == "unfinished")
        #expect(store.bufferedSegmentIDs.isEmpty)
        await adapter.finish()
        coordinator.finish()
        let end = await translated.next()
        #expect(end == nil)
    }

    @Test func finishFlushesOnceAndCancelsPendingTimeout() async {
        let delay = ControlledTranslationDelay()
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let session = UUID()
        let adapter = LegacyTranslationAdapter(
            sessionID: session, store: store, coordinator: coordinator, sleep: delay.sleep
        )
        adapter.receive(transcriptEvent(sessionID: session, text: "unfinished"))
        var requested = delay.requests.makeAsyncIterator()
        _ = await requested.next()
        await adapter.finish()
        delay.fire()
        await adapter.finish()
        adapter.receive(transcriptEvent(sessionID: session, text: "too late."))
        coordinator.finish()
        var texts: [String] = []
        for await item in stream { texts.append(item.text) }
        #expect(texts == ["unfinished"])
        #expect(store.units.count == 1)
    }

    @Test func transcriptionOnlyStillRetainsFinalText() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        coordinator.finish()
        let session = UUID()
        let adapter = LegacyTranslationAdapter(sessionID: session, store: store, coordinator: coordinator)
        adapter.receive(transcriptEvent(sessionID: session, text: "Hello."))
        await adapter.finish()
        #expect(store.segments.map(\.english) == ["Hello."])
        #expect(store.units.first?.japanese == nil)
    }
}

@MainActor
private final class ControlledTranslationDelay {
    let requests: AsyncStream<Duration>
    private let requested: AsyncStream<Duration>.Continuation
    private let ticks: AsyncStream<Void>
    private let tick: AsyncStream<Void>.Continuation

    init() {
        (requests, requested) = AsyncStream.makeStream(of: Duration.self)
        (ticks, tick) = AsyncStream.makeStream(of: Void.self)
    }

    func sleep(_ duration: Duration) async throws {
        requested.yield(duration)
        for await _ in ticks { break }
        try Task.checkCancellation()
    }

    func fire() { tick.yield(()) }
}
