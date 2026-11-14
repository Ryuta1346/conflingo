/// Synchronous MainActor notifications. The subscriber owns the returned subscription.
@MainActor
final class EventSignal<Event> {
    private struct Entry {
        weak var subscription: EventSubscription<Event>?
    }
    private var entries: [Entry] = []

    func observe(_ action: @escaping (Event) -> Void) -> EventSubscription<Event> {
        entries.removeAll { $0.subscription?.isActive != true }
        let subscription = EventSubscription(action)
        entries.append(Entry(subscription: subscription))
        return subscription
    }

    func emit(_ event: Event) {
        entries.removeAll { $0.subscription?.isActive != true }
        // Snapshot membership, but consult each subscription at delivery time for cancellation.
        let current = entries
        for entry in current { entry.subscription?.receive(event) }
    }
}

@MainActor
final class EventSubscription<Event> {
    private var action: ((Event) -> Void)?
    fileprivate var isActive: Bool { action != nil }

    fileprivate init(_ action: @escaping (Event) -> Void) { self.action = action }
    func cancel() { action = nil }
    fileprivate func receive(_ event: Event) { action?(event) }
}
