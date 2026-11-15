import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DR5TransportTests {
    @Test func elapsedIncludesPauseFreezesOnEndAndResets() async throws {
        var now = 100.0
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(timeline: MeetingTimeline(now: { now })))
        #expect(meeting.elapsedTime == 0)
        now = 200
        #expect(meeting.elapsedTime == 0)
        meeting.consentConfirmed = true
        await meeting.start()
        now = 210
        #expect(meeting.elapsedTime == 10)
        await meeting.pause()
        now = 270
        #expect(meeting.elapsedTime == 70)
        #expect(meeting.transportStatus == .paused)
        await meeting.start()
        now = 280
        meeting.requestEnd()
        meeting.cancelEnd()
        #expect(meeting.elapsedTime == 80)
        now = 290
        meeting.requestEnd()
        let end = try #require(meeting.confirmEnd())
        await end.value
        now = 500
        #expect(meeting.elapsedTime == 90)
        #expect(meeting.transportStatus == .ended)
        meeting.requestDiscard()
        #expect(meeting.elapsedTime == 0)
        #expect(meeting.transportStatus == .ready)
    }

    @Test(arguments: AudioInputSelection.allCases)
    func selectedInputsOnlyAndFailedStopRemainsVisible(selection: AudioInputSelection) async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.inputSelection = selection
        #expect(Set(meeting.displayedInputOrigins) == selection.origins)
        meeting.consentConfirmed = true
        await meeting.start()
        let failing = selection == .microphone ? fixture.microphone : fixture.system
        let origin: AudioOrigin = selection == .microphone ? .microphone : .systemAudio
        failing.stopError = .stop
        await meeting.end()
        #expect(meeting.transportStatus == .stopFailed)
        meeting.inputSelection = origin == .microphone ? .systemAudio : .microphone
        #expect(meeting.displayedInputOrigins.contains(origin))
        failing.stopError = nil
        await meeting.retryStop()
        #expect(meeting.transportStatus == .ended)
    }

    @Test func cancellingBeforeInputKeepsZeroTime() async {
        var now = 10.0
        let fixture = DualFixture()
        let gate = TestGate()
        let meeting = MeetingWorkspace(controller: fixture.controller(timeline: MeetingTimeline(now: { now }), prepareModel: { locale in
            await gate.wait()
            return locale
        }))
        meeting.consentConfirmed = true
        let start = Task { await meeting.start() }
        await gate.entered.next()
        now = 90
        #expect(meeting.transportStatus == .preparing)
        #expect(meeting.elapsedTime == 0)
        let cancel = Task { await meeting.cancelPreparation() }
        await gate.cancelled.next()
        gate.release()
        await start.value
        await cancel.value
        #expect(meeting.transportStatus == .ready)
        #expect(meeting.elapsedTime == 0)
    }

    @Test func announcementsFollowStateOnceWithoutViewsOrClockTicks() async throws {
        var announcements: [String] = []
        var now = 0.0
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(timeline: MeetingTimeline(now: { now })),
                                       announceStatus: { announcements.append($0) })
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(try await waitForTestCondition { announcements.contains("会議：取得中") })
        let count = announcements.count
        now = 50
        _ = meeting.elapsedTime
        _ = meeting.transportStatus
        _ = meeting.transportStatus
        try await fixture.microphone.emit("本文更新は通知しない", time: 1)
        #expect(announcements.count == count)
        await meeting.pause()
        #expect(try await waitForTestCondition { announcements.last == "会議：一時停止" })
        await meeting.start()
        #expect(try await waitForTestCondition { announcements.last == "会議：取得中" })
        await meeting.end()
        #expect(try await waitForTestCondition { announcements.last == "会議：終了" })
        #expect(announcements.filter { $0 == "会議：取得中" }.count == 2)
        #expect(announcements.filter { $0 == "会議：終了" }.count == 1)
        #expect(!zip(announcements, announcements.dropFirst()).contains { $0 == $1 })
    }
}
