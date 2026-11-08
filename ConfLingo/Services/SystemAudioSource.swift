import AVFAudio
import CoreGraphics
import Foundation

@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream
    func stop() async throws
}

@MainActor
final class SystemAudioSource: AudioSource {
    let origin: AudioOrigin = .systemAudio
    private(set) var state: AudioSourceState = .idle
    var permissionStatus: AudioPermissionStatus { readPermission() }

    private let capture: any SystemAudioCapturing
    private let readPermission: @MainActor () -> AudioPermissionStatus
    private let askPermission: @MainActor () async -> Bool
    private var permissionTask: Task<Bool, Never>?
    private var startTask: Task<AudioFrameStream, any Error>?
    private var stopTask: Task<Void, any Error>?
    private var runID: UUID?

    init(
        capture: any SystemAudioCapturing = ScreenCaptureAudioCapture(),
        permissionStatus: @escaping @MainActor () -> AudioPermissionStatus = {
            CGPreflightScreenCaptureAccess() ? .granted : .unknown
        },
        requestPermission: @escaping @MainActor () async -> Bool = { CGRequestScreenCaptureAccess() }
    ) {
        self.capture = capture
        readPermission = permissionStatus
        askPermission = requestPermission
    }

    func requestPermission() async -> Bool {
        guard !Task.isCancelled else { return false }
        if permissionStatus == .granted { return true }
        let task: Task<Bool, Never>
        if let permissionTask {
            task = permissionTask
        } else {
            task = Task { await askPermission() }
            permissionTask = task
        }
        let allowed = await task.value
        permissionTask = nil
        return allowed && !Task.isCancelled
    }

    func start(targetFormat: AVAudioFormat) async throws -> AudioFrameStream {
        try Task.checkCancellation()
        guard state == .idle else { throw AudioSourceError.alreadyRunning }
        guard permissionStatus == .granted else { throw AudioSourceError.permissionDenied }
        let currentRun = UUID()
        runID = currentRun
        state = .starting
        let task = Task { try await capture.start(targetFormat: targetFormat) }
        startTask = task
        do {
            let stream = try await task.value
            try Task.checkCancellation()
            guard runID == currentRun, state == .starting else { throw CancellationError() }
            state = .running
            startTask = nil
            return stream
        } catch {
            if runID == currentRun { try await stop() }
            throw error
        }
    }

    func stop() async throws {
        if let stopTask {
            try await stopTask.value
            return
        }
        guard state != .idle else { return }
        state = .stopping
        let pendingStart = startTask
        let task = Task {
            defer { stopTask = nil }
            // SCStream may complete a start after cancellation. Wait before disposing it.
            _ = await pendingStart?.result
            try await capture.stop()
            state = .idle
            runID = nil
            startTask = nil
        }
        stopTask = task
        try await task.value
    }
}
