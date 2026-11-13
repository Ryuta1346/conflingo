import Foundation
import Observation

/// final セグメントの翻訳キュー。ID ベースの重複排除と AsyncStream による
/// `.translationTask` クロージャへの受け渡しを担う。
@MainActor
@Observable
final class TranslationCoordinator {
    enum PreparationState: Equatable {
        case idle, preparing, ready, failed(String)
    }

    private(set) var preparationState: PreparationState = .idle
    private var generation: UUID?

    func beginPreparation() -> UUID {
        finish()
        let next = UUID()
        generation = next
        preparationState = .preparing
        return next
    }

    func preparationFailed(generation: UUID, reason: String) {
        guard isCurrent(generation) else { return }
        preparationState = .failed(reason)
    }

    func prepared(generation: UUID, store: SessionStore) -> AsyncStream<PendingItem>? {
        guard isCurrent(generation), preparationState == .preparing else { return nil }
        let stream = attach()
        preparationState = .ready
        // 購読開始と保留分の投入を同じMainActor処理内で行い、新しい発話との逆転を防ぐ。
        for unit in store.untranslatedUnits { enqueue(id: unit.id, text: unit.english) }
        return stream
    }

    func isCurrent(_ generation: UUID) -> Bool {
        self.generation == generation && !Task.isCancelled
    }

    struct PendingItem: Sendable, Equatable {
        let id: UUID
        let text: String
    }

    private var continuation: AsyncStream<PendingItem>.Continuation?
    private var enqueuedIDs: Set<UUID> = []

    /// 新しい消費ストリームを生成する。`.translationTask` クロージャの（再）実行ごとに呼ぶ。
    /// 既存ストリームは finish され、dedup 状態はリセットされる。
    func attach() -> AsyncStream<PendingItem> {
        continuation?.finish()
        enqueuedIDs.removeAll()
        let (stream, newContinuation) = AsyncStream.makeStream(of: PendingItem.self)
        continuation = newContinuation
        return stream
    }

    func enqueue(id: UUID, text: String) {
        guard let continuation, !enqueuedIDs.contains(id) else { return }
        enqueuedIDs.insert(id)
        continuation.yield(PendingItem(id: id, text: text))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
        enqueuedIDs.removeAll()
        generation = nil
        preparationState = .idle
    }
}
