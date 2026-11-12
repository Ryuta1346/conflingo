import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingWorkspaceTests {
    @Test func meetingSharesInputExclusionWithConferenceAndProbes() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(owner: .meeting))
        meeting.consentConfirmed = true
        let token = try #require(fixture.activity.acquire(.conference))
        await meeting.start()
        #expect(meeting.phase == .idle)
        #expect(fixture.microphone.starts == 0)
        #expect(meeting.controller.lastError?.contains("Conference") == true)
        fixture.activity.release(token)
        await meeting.start()
        #expect(fixture.activity.owner == .meeting)
        #expect(fixture.activity.acquire(.dualTranscription) == nil)
        #expect(fixture.activity.acquire(.systemAudioProbe) == nil)
        await meeting.pause()
        #expect(fixture.activity.owner == nil)
    }

    @Test func deniedPermissionCanReturnToPreparationAndRetry() async {
        let fixture = DualFixture()
        fixture.microphonePermission.status = .undetermined
        fixture.microphonePermission.decision = false
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(meeting.phase == .idle)
        #expect(meeting.controller.lastError != nil)
        #expect(fixture.microphone.starts == 0)
        #expect(meeting.startedAt == nil)
        meeting.editPreparation()
        #expect(meeting.page == .setup)
        fixture.microphonePermission.decision = true
        fixture.microphonePermission.status = .granted
        await meeting.start()
        #expect(meeting.phase == .listening)
        await meeting.end()
    }

    @Test func navigatingAwayPausesButDoesNotEndOrDiscardMeeting() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        let navigation = ConferenceNavigation(destination: .meeting)
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("Keep across navigation", time: 1)
        navigation.request(.settings, phase: meeting.phase)
        await navigation.confirmNavigation(phase: { meeting.phase }, stop: meeting.pause)
        #expect(navigation.destination == .settings)
        #expect(meeting.page == .live)
        #expect(meeting.phase == .idle)
        #expect(meeting.store.finals.first?.text == "Keep across navigation")
        navigation.request(.meeting, phase: meeting.phase)
        await meeting.start()
        #expect(meeting.phase == .listening)
        await meeting.end()
    }

    @Test func consentIsRequiredAndNewMeetingClearsIt() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        await meeting.start()
        #expect(fixture.microphone.starts == 0)
        #expect(meeting.page == .setup)
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(meeting.phase == .listening)
        await meeting.end()
        #expect(meeting.page == .review)
        meeting.requestDiscard()
        #expect(meeting.page == .setup)
        #expect(!meeting.consentConfirmed)
    }

    @Test func pauseResumePreservesSessionAndEndDrainsFinals() async throws {
        let fixture = DualFixture()
        var now = 100.0
        let meeting = MeetingWorkspace(controller: fixture.controller(timeline: MeetingTimeline(now: { now })))
        meeting.consentConfirmed = true
        meeting.name = "Design review"
        await meeting.start()
        let id = meeting.store.sessionID
        try await fixture.microphone.emit("first", time: 1)
        await meeting.pause()
        #expect(meeting.page == .live)
        #expect(meeting.phase == .idle)
        now = 120
        await meeting.start()
        fixture.system.finalOnStop = "last"
        await meeting.end()
        #expect(meeting.page == .review)
        #expect(meeting.store.sessionID == id)
        #expect(meeting.store.finals.map(\.text) == ["first", "last"])
        #expect(meeting.store.finals.map(\.startOffset) == [1, 29])
        #expect(meeting.name == "Design review")
    }

    @Test func endWaitsForFinalAndIgnoresDoubleActions() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        let gate = TestGate()
        fixture.system.finishGate = gate
        fixture.system.finalOnStop = "final during stop"
        let end = Task { await meeting.end() }
        await gate.entered.next()
        await meeting.end()
        await meeting.start()
        meeting.requestDiscard()
        #expect(meeting.page == .live)
        #expect(meeting.isBusy)
        #expect(!meeting.showsDiscardConfirmation)
        #expect(fixture.microphone.starts == 1)
        gate.release()
        await end.value
        #expect(meeting.page == .review)
        #expect(meeting.store.finals.first?.text == "final during stop")
    }

    @Test func failedEndRetainsIntentUntilRetryAndCannotDiscard() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        fixture.system.stopError = .stop
        await meeting.end()
        #expect(meeting.page == .live)
        #expect(meeting.phase == .stopping)
        #expect(!meeting.isBusy)
        meeting.requestDiscard()
        #expect(!meeting.showsDiscardConfirmation)
        fixture.system.stopError = nil
        await meeting.retryStop()
        #expect(meeting.page == .review)
        #expect(meeting.controller.lastError == nil)
        #expect(fixture.microphone.inputStops == 1)
    }

    @Test func cancellingPreparationRejectsLateCompletion() async {
        let fixture = DualFixture()
        let gate = TestGate()
        let meeting = MeetingWorkspace(controller: fixture.controller(prepareModel: { locale in
            await gate.wait()
            return locale
        }))
        meeting.consentConfirmed = true
        let start = Task { await meeting.start() }
        await gate.entered.next()
        let cancel = Task { await meeting.cancelPreparation() }
        await gate.cancelled.next()
        gate.release()
        await start.value
        await cancel.value
        #expect(meeting.page == .setup)
        #expect(meeting.phase == .idle)
        #expect(fixture.microphone.starts + fixture.system.starts == 0)
        #expect(meeting.startedAt == nil)
    }

    @Test func startDateTracksFirstInputAndSurvivesResumeUntilDiscard() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: FakeInsightClient(),
                                       credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        var firstInputBoundary = Date.distantFuture
        var secondInputBoundary = Date.distantFuture
        fixture.microphone.beforeInput = { firstInputBoundary = Date() }
        fixture.system.beforeInput = { secondInputBoundary = Date() }
        meeting.consentConfirmed = true
        await meeting.start()
        let startedAt = try #require(meeting.startedAt)
        #expect(startedAt >= firstInputBoundary)
        #expect(startedAt <= secondInputBoundary)
        await meeting.pause()
        await meeting.start()
        #expect(meeting.startedAt == startedAt)
        fixture.microphone.finalOnStop = "Synthetic final"
        await meeting.end()
        #expect(meeting.exportSnapshot?.startedAt == startedAt)
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.startedAt == nil)
    }

    @Test func retryAfterPermissionDenialRecordsActualInputStart() async throws {
        let fixture = DualFixture()
        fixture.microphonePermission.status = .undetermined
        fixture.microphonePermission.decision = false
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: FakeInsightClient(),
                                       credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(meeting.startedAt == nil)
        fixture.microphonePermission.decision = true
        fixture.microphonePermission.status = .granted
        var inputBoundary = Date.distantFuture
        fixture.microphone.beforeInput = { inputBoundary = Date() }
        await meeting.start()
        #expect(try #require(meeting.startedAt) >= inputBoundary)
        await meeting.end()
    }

    @Test func partialInputStartFailureRetainsActualStartOnRetry() async throws {
        let fixture = DualFixture()
        fixture.system.startError = .start
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: FakeInsightClient(),
                                       credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        var inputBoundary = Date.distantFuture
        fixture.microphone.beforeInput = { inputBoundary = Date() }
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(meeting.phase == .idle)
        let startedAt = try #require(meeting.startedAt)
        #expect(startedAt >= inputBoundary)
        fixture.system.startError = nil
        await meeting.start()
        #expect(meeting.startedAt == startedAt)
        await meeting.end()
    }

    @Test func inputFailureDoesNotPretendUserEndedMeeting() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("keep", time: 1)
        fixture.system.fail(DualFakeSpeech.Failure.recognition)
        await fixture.system.stopping.next()
        await meeting.controller.stop()
        #expect(meeting.page == .live)
        #expect(meeting.phase == .idle)
        #expect(meeting.store.finals.first?.text == "keep")
        #expect(meeting.controller.lastError != nil)
    }

    @Test func discardRequiresConfirmationAndCancellationKeepsTranscript() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("keep", time: 1)
        await meeting.end()
        let id = meeting.store.sessionID
        meeting.requestDiscard()
        #expect(meeting.showsDiscardConfirmation)
        meeting.showsDiscardConfirmation = false
        meeting.confirmDiscard()
        #expect(meeting.store.sessionID == id)
        #expect(meeting.store.finals.count == 1)
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.store.finals.isEmpty)
        #expect(meeting.store.sessionID != id)
        #expect(!meeting.consentConfirmed)
    }
}
