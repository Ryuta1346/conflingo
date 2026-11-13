import AVFAudio
import Foundation

enum AudioCaptureError: LocalizedError {
    case converterUnavailable
    case configurationChanged

    var errorDescription: String? {
        switch self {
        case .converterUnavailable:
            "マイク入力のフォーマット変換を初期化できませんでした。"
        case .configurationChanged:
            "マイクの機器構成が変更されたため、音声入力を停止しました。入力機器を確認して、もう一度開始してください。"
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
    private let engine: any MicrophoneCaptureEngine
    private let notificationCenter: NotificationCenter
    private var configurationObserver: (any NSObjectProtocol)?
    private var runID: UUID?
    private var continuation: AudioFrameStream.Continuation?
    private let diagnostics: AudioDiagnostics?

    init(diagnostics: AudioDiagnostics? = nil,
         engine: any MicrophoneCaptureEngine = SystemMicrophoneCaptureEngine(),
         notificationCenter: NotificationCenter = .default) {
        self.diagnostics = diagnostics
        self.engine = engine
        self.notificationCenter = notificationCenter
    }

    isolated deinit {
        if let configurationObserver { notificationCenter.removeObserver(configurationObserver) }
        if continuation != nil { engine.stop() }
        continuation?.finish()
    }

    func start(targetFormat: AVAudioFormat) throws -> AudioFrameStream {
        guard continuation == nil else { throw AudioSourceError.alreadyRunning }
        let hardwareFormat = engine.inputFormat

        guard let converter = BufferConverter(from: hardwareFormat, to: targetFormat, diagnostics: diagnostics) else {
            throw AudioCaptureError.converterUnavailable
        }

        let (stream, newContinuation) = AudioFrameStream.makeStream()
        continuation = newContinuation
        let currentRun = UUID()
        runID = currentRun
        configurationObserver = notificationCenter.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine.notificationObject, queue: nil
        ) { @Sendable [weak self] _ in
            // OS内部の通知キューではエンジンを停止・破棄しない。
            Task { @MainActor [weak self] in
                guard let self, self.runID == currentRun else { return }
                self.finish(throwing: AudioCaptureError.configurationChanged)
            }
        }

        // tap コールバックは音声スレッドで呼ばれる。@Sendable を明示しないと
        // @MainActor コンテキストの隔離を継承し、実行時の隔離アサーションでクラッシュする。
        let diagnostics = self.diagnostics
        engine.installTap(format: hardwareFormat) { @Sendable buffer in
            diagnostics?.record(.tap, origin: .microphone, samples: Int(buffer.frameLength),
                                sampleRate: buffer.format.sampleRate, channels: buffer.format.channelCount)
            guard let converted = converter.convert(buffer) else { return }
            diagnostics?.record(.converted, origin: .microphone, samples: Int(converted.frameLength),
                                sampleRate: converted.format.sampleRate, channels: converted.format.channelCount)
            guard let frame = AudioFrame(copying: converted) else {
                diagnostics?.record(.copyFailure, origin: .microphone)
                return
            }
            switch newContinuation.yield(frame) {
            case .enqueued: diagnostics?.record(.enqueued, origin: .microphone, samples: Int(converted.frameLength))
            case .dropped: diagnostics?.record(.yieldDropped, origin: .microphone)
            case .terminated: diagnostics?.record(.yieldTerminated, origin: .microphone)
            @unknown default: break
            }
        }

        do {
            try engine.start()
        } catch {
            stop()
            throw error
        }
        return stream
    }

    func stop() {
        finish()
    }

    private func finish(throwing error: (any Error)? = nil) {
        // 未開始・停止済みの場合、inputNode の取得による音声デバイス接続を避ける。
        guard let continuation else { return }
        self.continuation = nil
        runID = nil
        if let configurationObserver { notificationCenter.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        continuation.finish(throwing: error)
    }
}

/// AVAudioConverter は Sendable ではないが、installTap のコールバックは直列に呼ばれるため
/// 単一インスタンスへの逐次アクセスは安全。@unchecked Sendable で限定的に許可する。
private final class BufferConverter: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let diagnostics: AudioDiagnostics?

    init?(from source: AVAudioFormat, to target: AVAudioFormat, diagnostics: AudioDiagnostics?) {
        self.diagnostics = diagnostics
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
            diagnostics?.record(.conversionFailure, origin: .microphone)
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

        guard status != .error, conversionError == nil else {
            diagnostics?.record(.conversionFailure, origin: .microphone)
            return nil
        }
        guard output.frameLength > 0 else {
            diagnostics?.record(.conversionEmpty, origin: .microphone)
            return nil
        }
        return output
    }
}
