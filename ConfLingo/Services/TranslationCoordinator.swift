import Foundation

/// final セグメントの翻訳キュー。ID ベースの重複排除と AsyncStream による
/// `.translationTask` クロージャへの受け渡しを担う。
@MainActor
final class TranslationCoordinator {
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
        guard !enqueuedIDs.contains(id) else { return }
        enqueuedIDs.insert(id)
        continuation?.yield(PendingItem(id: id, text: text))
    }

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}
