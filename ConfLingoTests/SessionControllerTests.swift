import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SessionControllerTests {
    /// Stop 時、文末待ちのまま残ったバッファが翻訳単位として確定され翻訳キューに入ること。
    @Test func stopFlushesRemainingBufferedSegments() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let controller = SessionController()

        // 文末なしのセグメントをバッファに残した listening 状態を再現する
        let id = store.appendFinal("an unfinished segment without sentence end")!
        #expect(store.bufferSegment(id) == nil)
        store.phase = .listening

        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()

        #expect(store.phase == .idle)
        #expect(store.units.count == 1)
        #expect(store.bufferedSegmentIDs.isEmpty)
        var enqueued: [TranslationCoordinator.PendingItem] = []
        for await item in stream {
            enqueued.append(item)
        }
        #expect(enqueued.map(\.id) == [store.units[0].id])
    }

    /// Stop 時、バッファが空なら翻訳単位もキュー投入も発生しないこと。
    @Test func stopWithEmptyBufferDoesNotEnqueue() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let stream = coordinator.attach()
        let controller = SessionController()
        store.phase = .listening

        await controller.stop(store: store, coordinator: coordinator)
        coordinator.finish()

        #expect(store.phase == .idle)
        #expect(store.units.isEmpty)
        var enqueued: [TranslationCoordinator.PendingItem] = []
        for await item in stream {
            enqueued.append(item)
        }
        #expect(enqueued.isEmpty)
    }

    /// listening 以外の phase では stop が何もしないこと（二重 stop ガード）。
    @Test func stopIsNoOpWhenNotListening() async {
        let store = SessionStore()
        let coordinator = TranslationCoordinator()
        let controller = SessionController()
        let id = store.appendFinal("buffered text")!
        _ = store.bufferSegment(id)

        await controller.stop(store: store, coordinator: coordinator)

        #expect(store.phase == .idle)
        #expect(store.units.isEmpty)
        #expect(store.bufferedSegmentIDs.count == 1)
    }
}
