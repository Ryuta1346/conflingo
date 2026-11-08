import AppKit
import Testing
@testable import ConfLingo

@MainActor
struct MeetingPresentationTests {
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
        let low = MeetingInsight(kind: "質問候補", text: "low", priority: 0, evidenceIDs: [])
        let high = MeetingInsight(kind: "決定候補", text: "first high", priority: 2, evidenceIDs: [])
        let latest = MeetingInsight(kind: "リスク", text: "latest high", priority: 2, evidenceIDs: [])
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
