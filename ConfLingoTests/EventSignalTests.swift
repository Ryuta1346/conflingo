import Testing
@testable import ConfLingo

@MainActor
struct EventSignalTests {
    @Test func subscribersReceiveInOrderAndCancelIndependently() {
        let signal = EventSignal<Int>()
        var delivered: [String] = []
        let first = signal.observe { delivered.append("first:\($0)") }
        let second = signal.observe { delivered.append("second:\($0)") }
        defer { first.cancel(); second.cancel() }
        signal.emit(1)
        first.cancel()
        first.cancel()
        signal.emit(2)
        #expect(delivered == ["first:1", "second:1", "second:2"])
    }

    @Test func releasingSubscriptionStopsDeliveryAndReleasesHandler() {
        let signal = EventSignal<Int>()
        var delivered = 0
        var token: EventSubscription<Int>? = signal.observe { delivered += $0 }
        weak var released = token
        signal.emit(1)
        token = nil
        #expect(released == nil)
        signal.emit(2)
        #expect(delivered == 1)
    }

    @Test func cancellationDuringDeliverySkipsPendingSubscriber() {
        let signal = EventSignal<Int>()
        var delivered: [Int] = []
        var second: EventSubscription<Int>?
        let first = signal.observe { _ in second?.cancel() }
        second = signal.observe { delivered.append($0) }
        defer { first.cancel(); second?.cancel() }
        signal.emit(1)
        #expect(delivered.isEmpty)
    }

    @Test func subscriptionsAddedDuringDeliveryStartWithNextEvent() {
        let signal = EventSignal<Int>()
        var delivered: [Int] = []
        var added: EventSubscription<Int>?
        let first = signal.observe { _ in
            if added == nil { added = signal.observe { delivered.append($0) } }
        }
        defer { first.cancel(); added?.cancel() }
        signal.emit(1)
        #expect(delivered.isEmpty)
        signal.emit(2)
        #expect(delivered == [2])
    }
}
