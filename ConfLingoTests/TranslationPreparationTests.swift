import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct TranslationPreparationTests {
    @Test func preparationFailureReplacesWaitingButPreservesSourceAndFinishedTranslations() throws {
        let store = SessionStore()
        let done = try append("Translated.", to: store)
        store.applyTranslation(id: done.id, japanese: "翻訳済み。")
        _ = try append("Waiting.", to: store)
        let coordinator = TranslationCoordinator()
        let generation = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: generation, reason: "Download cancelled")
        _ = try append("Arrived after failure.", to: store)

        #expect(coordinator.preparationState == .failed("Download cancelled"))
        let entries = TranscriptPresentation.translation(store, preparation: coordinator.preparationState)
        #expect(entries.map(\.status) == [.final, .failed, .failed])
        #expect(entries[0].text == "翻訳済み。")
        #expect(entries[1].text.contains("準備できませんでした"))
        #expect(TranscriptPresentation.source(store).map(\.text) == ["Translated.", "Waiting.", "Arrived after failure."])
    }

    @Test func retryDeliversBacklogAndNewSpeechOnceInOrder() async throws {
        let store = SessionStore()
        let done = try append("Done.", to: store)
        store.applyTranslation(id: done.id, japanese: "完了。")
        let first = try append("First.", to: store)
        let coordinator = TranslationCoordinator()
        let failed = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: failed, reason: "offline")
        coordinator.enqueue(id: first.id, text: first.english)
        let second = try append("Second.", to: store)
        let retry = coordinator.beginPreparation()
        #expect(coordinator.preparationState == .preparing)
        let stream = try #require(coordinator.prepared(generation: retry, store: store))
        #expect(coordinator.preparationState == .ready)
        coordinator.enqueue(id: second.id, text: second.english)
        let third = try append("Third.", to: store)
        coordinator.enqueue(id: third.id, text: third.english)
        coordinator.finish()
        var received: [String] = []
        for await item in stream { received.append(item.text) }
        #expect(received == ["First.", "Second.", "Third."])
    }

    @Test func obsoletePreparationCannotOverwriteRetryOrAttachItsQueue() throws {
        let coordinator = TranslationCoordinator()
        let store = SessionStore()
        let old = coordinator.beginPreparation()
        let current = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: old, reason: "old failure")
        #expect(coordinator.preparationState == .preparing)
        #expect(coordinator.prepared(generation: old, store: store) == nil)
        _ = try #require(coordinator.prepared(generation: current, store: store))
        coordinator.preparationFailed(generation: old, reason: "late failure")
        #expect(coordinator.preparationState == .ready)
        #expect(!coordinator.isCurrent(old))
        #expect(coordinator.isCurrent(current))
        coordinator.finish()
    }

    @Test func switchingToTranscriptionClearsFailureAndRejectsLatePreparation() {
        let coordinator = TranslationCoordinator()
        let generation = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: generation, reason: "offline")
        coordinator.finish()
        coordinator.preparationFailed(generation: generation, reason: "late error")
        #expect(coordinator.preparationState == .idle)
        #expect(coordinator.prepared(generation: generation, store: SessionStore()) == nil)
    }

    @Test func retryCanFailAgainWithNewReason() {
        let coordinator = TranslationCoordinator()
        let first = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: first, reason: "cancelled")
        let retry = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: retry, reason: "offline")
        #expect(coordinator.preparationState == .failed("offline"))
    }

    @Test func cancelledTaskCannotReportFailureOrStartTranslating() async {
        let coordinator = TranslationCoordinator()
        let generation = coordinator.beginPreparation()
        let task = Task { @MainActor in
            coordinator.preparationFailed(generation: generation, reason: "cancelled task")
            #expect(coordinator.prepared(generation: generation, store: SessionStore()) == nil)
        }
        task.cancel()
        await task.value
        #expect(coordinator.preparationState == .preparing)
        coordinator.finish()
    }

    private func append(_ text: String, to store: SessionStore) throws -> TranslationUnit {
        let id = try #require(store.appendFinal(text))
        return try #require(store.bufferSegment(id))
    }
}
