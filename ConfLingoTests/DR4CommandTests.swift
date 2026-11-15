import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DR4CommandTests {
        @Test func commandsCannotStartWithoutConsentAndPauseInsteadOfEnding() async throws {
            let meeting = MeetingWorkspace(controller: DualFixture().controller())
            var requestedEnd = false
            var commands = SessionCommandActions.meeting(meeting, requestEnd: { requestedEnd = true })
            #expect(!commands.canToggle)
            commands.toggle()
            await Task.yield()
            #expect(meeting.page == .setup)
            meeting.consentConfirmed = true
            commands = .meeting(meeting, requestEnd: { requestedEnd = true })
            commands.toggle()
            try #require(try await waitForTestCondition { meeting.phase == .listening && !meeting.isBusy })
            commands = .meeting(meeting, requestEnd: { requestedEnd = true })
            commands.toggle()
            try #require(try await waitForTestCondition { meeting.phase == .idle && !meeting.isBusy })
            #expect(meeting.page == .live)
            commands = .meeting(meeting, requestEnd: { requestedEnd = true })
            let requestEnd = try #require(commands.end)
            requestEnd()
            #expect(requestedEnd)
            #expect(meeting.page == .live)
            await meeting.end()
        }
    }
}
