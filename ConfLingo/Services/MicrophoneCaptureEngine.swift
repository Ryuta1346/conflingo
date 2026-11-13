import AVFAudio
import Foundation

/// 機器への接続とtap操作だけを担うOS境界。
@MainActor
protocol MicrophoneCaptureEngine: AnyObject {
    var notificationObject: AnyObject { get }
    var inputFormat: AVAudioFormat { get }
    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    func start() throws
    func stop()
}

@MainActor
final class SystemMicrophoneCaptureEngine: MicrophoneCaptureEngine {
    private let engine = AVAudioEngine()
    var notificationObject: AnyObject { engine }
    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    func installTap(format: AVAudioFormat, receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { @Sendable buffer, _ in
            receive(buffer)
        }
    }

    func start() throws {
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
