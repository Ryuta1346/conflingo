import Foundation

/// 購読先ごとの有界キュー。消費処理や外部I/Oの完了は待たない。
actor TranscriptEventHub {
    enum Failure: Error, Equatable {
        case overflow
        case closed
        case concurrentRead
    }

    struct Subscription: Sendable {
        let id: UUID
        fileprivate let hub: TranscriptEventHub

        /// 一つの購読は一つの消費タスクから読む。
        func next() async throws -> TranscriptEvent? {
            try await hub.next(id)
        }

        func cancel() async {
            await hub.cancel(id)
        }
    }

    private struct Subscriber {
        var queue: [TranscriptEvent] = []
        var waiter: CheckedContinuation<TranscriptEvent?, any Error>?
        var finished = false
        var failure: Failure?
    }

    private let finalCapacity: Int
    private var subscribers: [UUID: Subscriber] = [:]
    private var finished = false

    init(finalCapacity: Int = 256) {
        precondition(finalCapacity > 0)
        self.finalCapacity = finalCapacity
    }

    func subscribe() -> Subscription {
        let id = UUID()
        if !finished { subscribers[id] = Subscriber() }
        return Subscription(id: id, hub: self)
    }

    /// 戻り値は今回finalを受け付けられなかった購読ID。
    @discardableResult
    func publish(_ event: TranscriptEvent) throws -> Set<UUID> {
        guard !finished else { throw Failure.closed }
        var failed: Set<UUID> = []
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id], !subscriber.finished else { continue }
            if let waiter = subscriber.waiter {
                subscriber.waiter = nil
                subscribers[id] = subscriber
                waiter.resume(returning: event)
                continue
            }
            subscriber.queue.removeAll { !$0.isFinal && $0.origin == event.origin }
            if event.isFinal && subscriber.queue.filter(\.isFinal).count >= finalCapacity {
                subscriber.finished = true
                subscriber.failure = .overflow
                subscriber.queue.removeAll { !$0.isFinal }
                failed.insert(id)
            } else {
                subscriber.queue.append(event)
            }
            subscribers[id] = subscriber
        }
        return failed
    }

    func finish() {
        finished = true
        for id in Array(subscribers.keys) {
            guard var subscriber = subscribers[id] else { continue }
            subscriber.finished = true
            if let waiter = subscriber.waiter {
                subscribers.removeValue(forKey: id)
                waiter.resume(returning: nil)
            } else {
                subscribers[id] = subscriber
            }
        }
    }

    private func cancel(_ id: UUID) {
        let subscriber = subscribers.removeValue(forKey: id)
        subscriber?.waiter?.resume(returning: nil)
    }

    private func next(_ id: UUID) async throws -> TranscriptEvent? {
        try await withTaskCancellationHandler {
            guard !Task.isCancelled else {
                cancel(id)
                return nil
            }
            guard var subscriber = subscribers[id] else { return nil }
            guard subscriber.waiter == nil else { throw Failure.concurrentRead }
            if !subscriber.queue.isEmpty {
                let event = subscriber.queue.removeFirst()
                subscribers[id] = subscriber
                return event
            }
            if subscriber.finished {
                subscribers.removeValue(forKey: id)
                if let failure = subscriber.failure { throw failure }
                return nil
            }
            return try await withCheckedThrowingContinuation { continuation in
                subscriber.waiter = continuation
                subscribers[id] = subscriber
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
}
