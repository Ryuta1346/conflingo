import AVFAudio
import Foundation
import Observation

@MainActor
@Observable
final class SystemAudioProbeController {
    private(set) var phase: AudioSourceState = .idle
    private(set) var permission: AudioPermissionStatus = .unknown
    private(set) var lastError: String?
    private(set) var frameCount = 0
    private(set) var level: Double = 0

    private let source: any AudioSource
    private let now: @MainActor () -> TimeInterval
    private var runID: UUID?
    private var consumer: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var receivedFrames = 0
    @ObservationIgnored private var lastMeterTime = -Double.infinity

    init(source: any AudioSource = SystemAudioSource(), now: @escaping @MainActor () -> TimeInterval = {
        ProcessInfo.processInfo.systemUptime
    }) {
        self.source = source
        self.now = now
        permission = source.permissionStatus
    }

    func refreshPermission() { permission = source.permissionStatus }

    func requestAccess() async {
        guard phase == .idle else { return }
        let currentRun = UUID()
        runID = currentRun
        phase = .starting
        lastError = nil
        let allowed = await source.requestPermission()
        guard runID == currentRun else { return }
        permission = allowed ? source.permissionStatus : .denied
        if !allowed { lastError = Self.permissionGuidance }
        runID = nil
        phase = .idle
    }

    func start() async {
        guard phase == .idle, !Task.isCancelled else { return }
        let currentRun = UUID()
        runID = currentRun
        phase = .starting
        lastError = nil
        frameCount = 0
        receivedFrames = 0
        lastMeterTime = -.infinity
        level = 0
        let allowed = await source.requestPermission()
        guard runID == currentRun else { return }
        do {
            try Task.checkCancellation()
            permission = allowed ? source.permissionStatus : .denied
            guard allowed else {
                lastError = Self.permissionGuidance
                await stop()
                return
            }
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
                throw SystemAudioCaptureError.conversionFailed
            }
            let frames = try await source.start(targetFormat: format)
            guard runID == currentRun else { return }
            try Task.checkCancellation()
            phase = .running
            consumer = Task { [weak self] in
                do {
                    for try await frame in frames {
                        guard let self, self.runID == currentRun, !Task.isCancelled else { return }
                        self.receive(frame)
                    }
                } catch {
                    guard let self, self.runID == currentRun, !Task.isCancelled else { return }
                    self.lastError = error.localizedDescription
                }
                guard let self, self.runID == currentRun else { return }
                await self.stop()
            }
        } catch {
            guard runID == currentRun else { return }
            if !(error is CancellationError) { lastError = error.localizedDescription }
            await stop()
        }
    }

    func stop() async {
        if let stopTask {
            await stopTask.value
            return
        }
        guard phase != .idle else { return }
        runID = nil
        phase = .stopping
        consumer?.cancel()
        consumer = nil
        let task = Task {
            do {
                try await source.stop()
                phase = .idle
            } catch {
                lastError = "停止を完了できませんでした。停止を再試行してください: \(error.localizedDescription)"
            }
            frameCount = receivedFrames
            level = 0
            stopTask = nil
        }
        stopTask = task
        await task.value
    }

    private func receive(_ frame: AudioFrame) {
        receivedFrames += 1
        let time = now()
        guard time - lastMeterTime >= 0.1 else { return }
        lastMeterTime = time
        frameCount = receivedFrames
        let count = Int(frame.buffer.frameLength)
        guard count > 0, let samples = frame.buffer.floatChannelData?[0] else {
            level = 0
            return
        }
        var squares = 0.0
        for index in 0..<count { squares += Double(samples[index]) * Double(samples[index]) }
        level = min(1, sqrt(squares / Double(count)))
    }

    private static let permissionGuidance = "システム設定 > プライバシーとセキュリティ > 画面収録とシステムオーディオ録音でConfLingoを許可してください。変更後はアプリの再起動が必要な場合があります。"
}
