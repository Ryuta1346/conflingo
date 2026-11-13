import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AudioInputUseTests {
    @Test func conferenceRejectsCompetingUseBeforeRequestingPermissionAndReleasesAfterStop() async {
        let activity = AudioInputUse()
        let other = activity.acquire(.dualTranscription)
        let speech = DualFakeSpeech()
        let permission = StubMicrophonePermission(status: .undetermined)
        let controller = SessionController(audioSource: permission.source(capture: StubAudioCapture()),
            speechService: speech, activity: activity)
        let store = SessionStore()
        let translations = TranslationCoordinator()
        await controller.start(store: store, coordinator: translations, locale: .current)
        #expect(store.phase == .idle)
        #expect(permission.requests == 0)
        #expect(speech.starts == 0)
        #expect(controller.lastError?.contains("使用中") == true)
        activity.release(other)
        await controller.start(store: store, coordinator: translations, locale: .current)
        #expect(activity.owner == .conference)
        await controller.stop(store: store, coordinator: translations)
        #expect(activity.owner == nil)
    }

    @Test func deniedConferencePermissionReleasesOwnership() async {
        let activity = AudioInputUse()
        let controller = SessionController(audioSource: StubMicrophonePermission(status: .denied).source(capture: StubAudioCapture()),
            speechService: DualFakeSpeech(), activity: activity)
        await controller.start(store: SessionStore(), coordinator: TranslationCoordinator(), locale: .current)
        #expect(activity.owner == nil)
    }

    @Test func probeRetainsUseOnFailedStopAndRejectsCompetingStart() async {
        let activity = AudioInputUse()
        let capture = StubSystemCapture()
        let source = SystemAudioSource(capture: capture, permissionStatus: { .granted })
        let probe = SystemAudioProbeController(source: source, activity: activity)
        let other = activity.acquire(.conference)
        await probe.start()
        #expect(capture.starts == 0)
        #expect(probe.lastError?.contains("使用中") == true)
        activity.release(other)
        await probe.start()
        #expect(activity.owner == .systemAudioProbe)
        capture.failStop = true
        await probe.stop()
        #expect(activity.owner == .systemAudioProbe)
        capture.failStop = false
        await probe.stop()
        #expect(activity.owner == nil)
    }

    @Test func staleReleaseCannotUnlockNewOwner() {
        let activity = AudioInputUse()
        let first = activity.acquire(.conference)
        activity.release(first)
        let second = activity.acquire(.conference)
        activity.release(first)
        #expect(activity.owner == .conference)
        #expect(activity.acquire(.dualTranscription) == nil)
        activity.release(second)
        #expect(activity.owner == nil)
    }
}
