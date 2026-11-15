import AppKit
import Testing
@testable import ConfLingo

@MainActor
struct DR4CommandTests {
    @Test func commandsCannotStartWithoutConsentAndPauseInsteadOfEnding() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        var requestedEnd = false
        var commands = SessionCommandActions.meeting(meeting, requestEnd: { requestedEnd = true })
        #expect(!commands.canToggle)
        commands.toggle()
        await Task.yield()
        #expect(meeting.page == .setup)
        meeting.consentConfirmed = true
        commands = .meeting(meeting, requestEnd: { requestedEnd = true })
        commands.toggle()
        #expect(try await waitForTestCondition { meeting.phase == .listening })
        commands = .meeting(meeting, requestEnd: { requestedEnd = true })
        commands.toggle()
        #expect(try await waitForTestCondition { meeting.phase == .idle })
        #expect(meeting.page == .live)
        commands.end?()
        #expect(requestedEnd)
        #expect(meeting.page == .live)
        await meeting.end()
    }
}
