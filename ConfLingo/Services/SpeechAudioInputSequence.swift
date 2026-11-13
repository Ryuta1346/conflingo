import Speech

/// 入力の異常終了を認識結果とは独立して通知する。追加のバッファや供給タスクは作らない。
struct SpeechAudioInputSequence: AsyncSequence, Sendable {
    typealias Element = AnalyzerInput
    let frames: AudioFrameStream
    let origin: AudioOrigin
    let diagnostics: AudioDiagnostics?
    let onFailure: @MainActor (any Error) -> Void

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(frames: frames.makeAsyncIterator(), origin: origin,
                      diagnostics: diagnostics, onFailure: onFailure)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var frames: AudioFrameStream.AsyncIterator
        let origin: AudioOrigin
        let diagnostics: AudioDiagnostics?
        let onFailure: @MainActor (any Error) -> Void
        private var finished = false

        init(frames: AudioFrameStream.AsyncIterator, origin: AudioOrigin,
             diagnostics: AudioDiagnostics?, onFailure: @escaping @MainActor (any Error) -> Void) {
            self.frames = frames
            self.origin = origin
            self.diagnostics = diagnostics
            self.onFailure = onFailure
        }

        mutating func next() async throws -> AnalyzerInput? {
            try await next(isolation: nil)
        }

        mutating func next(isolation actor: isolated (any Actor)?) async throws -> AnalyzerInput? {
            guard !finished else { return nil }
            do {
                guard let frame = try await frames.next(isolation: actor) else { finished = true; return nil }
                diagnostics?.record(.consumed, origin: origin, samples: Int(frame.buffer.frameLength),
                                    sampleRate: frame.buffer.format.sampleRate, channels: frame.buffer.format.channelCount)
                return AnalyzerInput(buffer: frame.buffer)
            } catch {
                finished = true
                if !Task.isCancelled { await onFailure(error) }
                throw error
            }
        }
    }
}
