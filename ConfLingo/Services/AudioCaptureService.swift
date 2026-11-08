import AVFAudio
import Foundation

enum AudioCaptureError: LocalizedError {
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .converterUnavailable:
            "マイク入力のフォーマット変換を初期化できませんでした。"
        }
    }
}

@MainActor
protocol AudioCapturing: AnyObject {
    func start(targetFormat: AVAudioFormat) throws -> AudioFrameStream
    func stop()
}

/// AVAudioEngine のマイク入力を指定PCMフォーマットへ変換するOS境界。
@MainActor
final class AudioCaptureService: AudioCapturing {
    private let engine = AVAudioEngine()
    private var continuation: AudioFrameStream.Continuation?

    func start(targetFormat: AVAudioFormat) throws -> AudioFrameStream {
        guard continuation == nil else { throw AudioSourceError.alreadyRunning }
        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = BufferConverter(from: hardwareFormat, to: targetFormat) else {
            throw AudioCaptureError.converterUnavailable
        }

        let (stream, newContinuation) = AudioFrameStream.makeStream()
        continuation = newContinuation

        // tap コールバックは音声スレッドで呼ばれる。@Sendable を明示しないと
        // @MainActor コンテキストの隔離を継承し、実行時の隔離アサーションでクラッシュする。
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { @Sendable buffer, _ in
            if let converted = converter.convert(buffer), let frame = AudioFrame(copying: converted) {
                newContinuation.yield(frame)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            newContinuation.finish()
            continuation = nil
            throw error
        }
        return stream
    }

    func stop() {
        // 未開始・停止済みの場合、inputNode の取得による音声デバイス接続を避ける。
        guard continuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation?.finish()
        continuation = nil
    }
}

/// AVAudioConverter は Sendable ではないが、installTap のコールバックは直列に呼ばれるため
/// 単一インスタンスへの逐次アクセスは安全。@unchecked Sendable で限定的に許可する。
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    init?(from source: AVAudioFormat, to target: AVAudioFormat) {
        targetFormat = target
        if source == target {
            converter = nil
        } else {
            guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
            self.converter = converter
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        // 入力ブロックは convert() の実行中に同一スレッドで同期的に呼ばれるため安全
        nonisolated(unsafe) var consumed = false
        nonisolated(unsafe) let inputBuffer = buffer
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, conversionError == nil, output.frameLength > 0 else { return nil }
        return output
    }
}
