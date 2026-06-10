import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct TranslationQueueTests {
    @Test func enqueueDeduplicatesByID() async {
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let id = UUID()
        coordinator.enqueue(id: id, text: "Hello")
        coordinator.enqueue(id: id, text: "Hello")
        coordinator.finish()

        var items: [TranslationCoordinator.PendingItem] = []
        for await item in stream { items.append(item) }
        #expect(items.count == 1)
    }

    @Test func enqueuePreservesOrder() async {
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        coordinator.enqueue(id: UUID(), text: "First")
        coordinator.enqueue(id: UUID(), text: "Second")
        coordinator.finish()

        var items: [TranslationCoordinator.PendingItem] = []
        for await item in stream { items.append(item) }
        #expect(items.map(\.text) == ["First", "Second"])
    }

    @Test func attachResetsDedupAndStream() async {
        let coordinator = TranslationCoordinator()
        let first = coordinator.attach()
        let id = UUID()
        coordinator.enqueue(id: id, text: "Hello")

        let second = coordinator.attach()
        coordinator.enqueue(id: id, text: "Hello")
        coordinator.finish()

        var firstItems: [TranslationCoordinator.PendingItem] = []
        for await item in first { firstItems.append(item) }
        var secondItems: [TranslationCoordinator.PendingItem] = []
        for await item in second { secondItems.append(item) }
        #expect(firstItems.count == 1)
        #expect(secondItems.count == 1)
    }

    @Test func enqueueWithoutAttachIsDropped() async {
        let coordinator = TranslationCoordinator()
        coordinator.enqueue(id: UUID(), text: "Hello")

        let stream = coordinator.attach()
        coordinator.finish()
        var items: [TranslationCoordinator.PendingItem] = []
        for await item in stream { items.append(item) }
        #expect(items.isEmpty)
    }
}
