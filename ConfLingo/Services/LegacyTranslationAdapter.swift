import Foundation

/// Conferenceの字幕・翻訳仕様を会話イベントへ接続する。
@MainActor
final class LegacyTranslationAdapter {
    static let bufferFlushTimeout: Duration = .seconds(4)

    private let sessionID: UUID
    private let store: SessionStore
    private let coordinator: TranslationCoordinator
    private let sleep: @MainActor (Duration) async throws -> Void
    private var latest: [UUID: TranscriptEvent] = [:]
    private var flushTask: Task<Void, Never>?
    private var finished = false

    init(
        sessionID: UUID, store: SessionStore, coordinator: TranslationCoordinator,
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.sessionID = sessionID
        self.store = store
        self.coordinator = coordinator
        self.sleep = sleep
    }

    func receive(_ event: TranscriptEvent) {
        guard !finished, event.sessionID == sessionID, event.origin == .microphone,
              !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let previous = latest[event.id] {
            guard !previous.isFinal, event.revision > previous.revision else { return }
        }
        latest[event.id] = event
        if !event.isFinal {
            store.updateVolatile(event.text)
            return
        }
        store.updateVolatile("")
        guard let id = store.appendFinal(event.text, startTime: event.sourceStartTime) else { return }
        flushTask?.cancel()
        if let unit = store.bufferSegment(id) {
            coordinator.enqueue(id: unit.id, text: unit.english)
            flushTask = nil
        } else {
            let sleep = self.sleep
            flushTask = Task { [weak self] in
                do {
                    try await sleep(Self.bufferFlushTimeout)
                    guard !Task.isCancelled else { return }
                    self?.flush()
                } catch { /* 停止・次の確定字幕でタイマーを取り消す。 */ }
            }
        }
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        flushTask?.cancel()
        await flushTask?.value
        flushTask = nil
        flush()
        store.updateVolatile("")
    }

    private func flush() {
        if let unit = store.flushBuffer() {
            coordinator.enqueue(id: unit.id, text: unit.english)
        }
    }
}
