import AVFAudio
import Foundation

enum AudioPermissionStatus: Sendable {
    case undetermined, granted, denied, unknown
}

enum AudioSourceState: Sendable {
    case idle, starting, running, stopping
}

enum AudioSourceError: LocalizedError {
    case permissionDenied
    case alreadyRunning

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "音声入力へのアクセスが許可されていません。"
        case .alreadyRunning:
            "音声入力はすでに開始されています。"
        }
    }
}

/// コールバックの再利用バッファから独立したPCM。
/// SendableでないAVAudioPCMBufferを所有し、発行後は供給側・消費側とも変更しない。
struct AudioFrame: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(copying buffer: AVAudioPCMBuffer) {
        guard let owned = buffer.copy() as? AVAudioPCMBuffer else { return nil }
        self.buffer = owned
    }
}

@MainActor
protocol AudioSource: AnyObject {
    var origin: AudioOrigin { get }
    var permissionStatus: AudioPermissionStatus { get }
    var state: AudioSourceState { get }
    func requestPermission() async -> Bool
    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<AudioFrame>
    func stop()
}
