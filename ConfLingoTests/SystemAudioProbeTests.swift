import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SystemAudioProbeTests {
    @Test func deniedAccessDisplaysGuidanceWithoutStarting() async {
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .unknown }, requestPermission: { false })
        let probe = SystemAudioProbeController(source: source)
        #expect(probe.phase == .idle)
        #expect(capture.starts == 0)
        await probe.start()
        #expect(probe.phase == .idle)
        #expect(probe.permission == .denied)
        #expect(probe.lastError?.contains("システム設定") == true)
        #expect(capture.starts == 0)
    }

    @Test func closingWhilePermissionIsPendingDoesNotStartLater() async {
        let prompted = TestSignal()
        let release = TestSignal()
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .unknown }, requestPermission: {
            prompted.signal()
            await release.next()
            return true
        })
        let probe = SystemAudioProbeController(source: source)
        let task = Task { await probe.start() }
        await prompted.next()
        await probe.stop()
        release.signal()
        await task.value
        #expect(probe.phase == .idle)
        #expect(capture.starts == 0)
    }

    @Test func startReceivesMetricsAndCloseStopsInput() async throws {
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        let metered = TestSignal()
        var time = 0.0
        let probe = SystemAudioProbeController(source: source, now: {
            time += 1
            metered.signal()
            return time
        })
        await probe.start()
        #expect(probe.phase == .running)
        let format = try makeFormat()
        capture.continuation?.yield(try #require(AudioFrame(copying: makeBuffer([0.5, -0.5], format: format))))
        await metered.next()
        #expect(probe.frameCount == 1)
        #expect(abs(probe.level - 0.5) < 0.001)
        await probe.stop()
        #expect(probe.phase == .idle)
        #expect(probe.level == 0)
        #expect(capture.stops == 1)
    }

    @Test func failureIsVisibleAndCleanupCanBeRetried() async {
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        let probe = SystemAudioProbeController(source: source)
        await probe.start()
        capture.failStop = true
        await probe.stop()
        #expect(probe.phase == .stopping)
        #expect(probe.lastError != nil)
        capture.failStop = false
        await probe.stop()
        #expect(probe.phase == .idle)
    }

    @Test func streamFailureStopsCaptureAndKeepsErrorVisible() async {
        let capture = StubSystemCapture()
        capture.holdStop = true
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        let probe = SystemAudioProbeController(source: source)
        await probe.start()
        capture.continuation?.finish(throwing: StubSystemCapture.Failure.runtime)
        await capture.stopping.next()
        #expect(probe.lastError != nil)
        capture.releaseStop.signal()
        await probe.stop()
        #expect(probe.phase == .idle)
        #expect(capture.stops == 1)
        #expect(probe.lastError != nil)
    }
}
