import AVFAudio
import Foundation

@MainActor
final class MicrophoneAudioSource: AudioSource {
    let origin: AudioOrigin = .microphone
    private(set) var state: AudioSourceState = .idle
    var permissionStatus: AudioPermissionStatus { readPermission() }

    private let capture: any AudioCapturing
    private let readPermission: @MainActor () -> AudioPermissionStatus
    private let askPermission: @MainActor () async -> Bool
    private var permissionTask: Task<Bool, Never>?

    init(
        capture: any AudioCapturing = AudioCaptureService(),
        permissionStatus: @escaping @MainActor () -> AudioPermissionStatus = MicrophoneAudioSource.systemPermission,
        requestPermission: @escaping @MainActor () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.capture = capture
        readPermission = permissionStatus
        askPermission = requestPermission
    }

    func requestPermission() async -> Bool {
        guard !Task.isCancelled else { return false }
        switch permissionStatus {
        case .granted: return true
        case .denied, .unknown: return false
        case .undetermined: break
        }
        // OSのダイアログは共有し、呼び出し元のキャンセルで他の要求を取り消さない。
        let task: Task<Bool, Never>
        if let permissionTask {
            task = permissionTask
        } else {
            task = Task { await askPermission() }
            permissionTask = task
        }
        let granted = await task.value
        permissionTask = nil
        return granted && !Task.isCancelled
    }

    func start(targetFormat: AVAudioFormat) throws -> AsyncStream<AudioFrame> {
        try Task.checkCancellation()
        guard state == .idle else { throw AudioSourceError.alreadyRunning }
        guard permissionStatus == .granted else { throw AudioSourceError.permissionDenied }
        state = .starting
        do {
            let stream = try capture.start(targetFormat: targetFormat)
            state = .running
            return stream
        } catch {
            state = .stopping
            capture.stop()
            state = .idle
            throw error
        }
    }

    func stop() {
        guard state == .running else { return }
        state = .stopping
        capture.stop()
        state = .idle
    }

    private static func systemPermission() -> AudioPermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .undetermined
        @unknown default: .unknown
        }
    }
}
