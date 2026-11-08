import AppKit
import Testing
@testable import ConfLingo

@MainActor
struct MeetingPresentationTests {
    @Test func expandingMeetingDoesNotCancelPreparation() async {
        let fixture = DualFixture()
        let gate = TestGate()
        let meeting = MeetingWorkspace(controller: fixture.controller(prepareModel: { locale in
            await gate.wait()
            return locale
        }))
        meeting.consentConfirmed = true
        let start = Task { await meeting.start() }
        await gate.entered.next()
        let navigation = ConferenceNavigation(destination: .settings)
        #expect(navigation.requestMeetingExpansion(conferencePhase: .idle))
        #expect(navigation.destination == .meeting)
        #expect(!navigation.showsStopConfirmation)
        #expect(meeting.phase == .preparing)
        let cancel = Task { await meeting.cancelPreparation() }
        await gate.cancelled.next()
        gate.release()
        await start.value
        await cancel.value
    }

    @Test func expandingMeetingPreservesConferenceStopConfirmation() async {
        let navigation = ConferenceNavigation(destination: .live)
        var conferencePhase = SessionPhase.listening
        #expect(!navigation.requestMeetingExpansion(conferencePhase: conferencePhase))
        #expect(navigation.showsStopConfirmation)
        #expect(navigation.destination == .live)
        navigation.cancelNavigation()
        #expect(navigation.destination == .live)
        #expect(!navigation.requestMeetingExpansion(conferencePhase: conferencePhase))
        await navigation.confirmNavigation(phase: { conferencePhase }) { conferencePhase = .idle }
        #expect(navigation.destination == .meeting)
    }

    @Test(arguments: [SessionPhase.preparing, .stopping])
    func expandingMeetingWaitsForConferenceProcessing(phase: SessionPhase) {
        let navigation = ConferenceNavigation(destination: .settings)
        #expect(!navigation.requestMeetingExpansion(conferencePhase: phase))
        #expect(navigation.destination == .settings)
        #expect(!navigation.showsStopConfirmation)
    }

    @Test func partialsKeepChronologicalPositionWhenFinalized() {
        let meeting = MeetingWorkspace(controller: DualFixture().controller())
        let earlierID = UUID()
        let laterID = UUID()
        func event(_ id: UUID, origin: AudioOrigin, time: Double, final: Bool, revision: Int) -> TranscriptEvent {
            TranscriptEvent(id: id, sessionID: meeting.store.sessionID, origin: origin,
                            languageCode: "en-US", startOffset: time, endOffset: time + 1,
                            text: "t=\(time)", isFinal: final, revision: revision, sourceStartTime: time)
        }
        meeting.store.receive(event(earlierID, origin: .microphone, time: 10, final: false, revision: 1))
        meeting.store.receive(event(laterID, origin: .systemAudio, time: 12, final: true, revision: 1))
        #expect(meeting.transcriptEvents.map(\.id) == [earlierID, laterID])
        meeting.store.receive(event(earlierID, origin: .microphone, time: 10, final: false, revision: 2))
        #expect(meeting.transcriptEvents.map(\.id) == [earlierID, laterID])
        meeting.store.receive(event(earlierID, origin: .microphone, time: 10, final: true, revision: 3))
        #expect(meeting.transcriptEvents.map(\.id) == [earlierID, laterID])
        #expect(meeting.transcriptEvents.allSatisfy { $0.isFinal })
    }

    @Test func equalTimeTranscriptEventsKeepStableOrder() {
        let meeting = MeetingWorkspace(controller: DualFixture().controller())
        let ids = [UUID(), UUID(), UUID()]
        for (index, id) in ids.enumerated() {
            meeting.store.receive(TranscriptEvent(id: id, sessionID: meeting.store.sessionID,
                                                 origin: .microphone, languageCode: "ja-JP",
                                                 startOffset: 10, endOffset: 11, text: "\(index)",
                                                 isFinal: index < 2, revision: 1, sourceStartTime: 10))
        }
        #expect(meeting.transcriptEvents.map(\.id) == ids)
    }

    @Test func repeatedEvidenceRequestsRemainObservable() {
        let meeting = MeetingWorkspace(controller: DualFixture().controller())
        let event = TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .microphone,
                                    languageCode: "ja-JP", startOffset: 0, endOffset: 1,
                                    text: "根拠", isFinal: true, revision: 1, sourceStartTime: 0)
        meeting.store.receive(event)
        meeting.revealEvidence(event.id)
        let request = meeting.evidenceRequest
        meeting.revealEvidence(event.id)
        #expect(meeting.evidenceRequest != request)
        #expect(meeting.selectedEvidence == event.id)
    }

    @Test func closingCurrentDestinationStillAsksToStop() {
        let nav = ConferenceNavigation(destination: .home)
        nav.request(.home, phase: .listening, forceConfirmation: true)
        #expect(nav.showsStopConfirmation)
        nav.cancelNavigation()
        #expect(nav.destination == .home)
    }
    @Test func evidenceUsesExactFinalIDAndMissingEvidenceIsNotInvented() {
        let meeting = MeetingWorkspace(controller: DualFixture().controller())
        let event = TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .systemAudio,
                                    languageCode: "en-US", startOffset: 12, endOffset: 14,
                                    text: "Can we ship?", isFinal: true, revision: 1, sourceStartTime: 12)
        meeting.store.receive(event)
        #expect(meeting.evidence(for: event.id) == event)
        #expect(meeting.evidence(for: UUID()) == nil)
    }

    @Test func floatingSelectsNewestOfHighestPriorityAndDoesNotConfirmCandidates() {
        let low = MeetingInsight(kind: .followUpQuestion, text: "low", priority: 0, evidenceIDs: [])
        let high = MeetingInsight(kind: .decisionCandidate, text: "first high", priority: 2, evidenceIDs: [])
        let latest = MeetingInsight(kind: .risk, text: "latest high", priority: 2, evidenceIDs: [])
        #expect(MeetingInsight.featured(in: [high, low, latest])?.id == latest.id)
        #expect(MeetingInsight.featured(in: []) == nil)
    }

    @Test func offscreenFrameIsRestoredInsideAvailableDisplay() {
        let display = NSRect(x: -1440, y: 20, width: 1440, height: 880)
        let old = NSRect(x: 4000, y: 900, width: 600, height: 700)
        let restored = MeetingFloatingPanel.constrained(old, to: [display])
        #expect(display.contains(restored))
        #expect(restored.size == old.size)
        let huge = MeetingFloatingPanel.constrained(NSRect(x: 0, y: 0, width: 4000, height: 4000), to: [display])
        #expect(display.contains(huge))
    }

    @Test func meetingNavigationWaitsForStopAndRetainsDestinationOnFailure() async {
        let nav = ConferenceNavigation(destination: .meeting)
        var phase = SessionPhase.listening
        nav.request(.settings, phase: phase)
        await nav.confirmNavigation(phase: { phase }) { phase = .stopping }
        #expect(nav.destination == .meeting)
        phase = .listening
        nav.request(.settings, phase: phase)
        await nav.confirmNavigation(phase: { phase }) { phase = .idle }
        #expect(nav.destination == .settings)
    }
}
