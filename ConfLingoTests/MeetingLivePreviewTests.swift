import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct MeetingLivePreviewTests {
    @Test(arguments: [
        ([String](), false),
        (["--meeting-live-ai"], false),
        (["--ui-preview", "--meeting-live-ai"], false),
        (["--meeting-preview"], false),
        (["--meeting-preview", "--meeting-live-ai"], true)
    ])
    func realAIRequiresBothExplicitFlags(arguments: [String], expected: Bool) {
        #expect(MeetingPreview.liveAIEnabled(arguments: arguments) == expected)
    }

    @Test(arguments: ["live", "offline", "sending"])
    func livePreviewStartsWithSyntheticTranscriptAndNoFabricatedAnswers(scenario: String) async {
        let meeting = MeetingPreview.make(activity: AudioInputUse(), scenario: scenario, liveAI: true)
        await MeetingPreview.prepare(meeting, scenario: scenario)
        #expect(meeting.phase == .listening)
        #expect(meeting.store.finals.count == 12)
        #expect(meeting.insights.isEmpty)
        #expect(!meeting.ai.permitted)
        #expect(!meeting.ai.automaticEnabled)
        #expect(meeting.credentials.store is KeychainAPIKeyStore)
        #expect(meeting.previewUsesLiveAI)
        #expect(meeting.aiStatus == meeting.ai.statusText)
        await meeting.end()
    }

    @Test func mockPreviewStillAnswersWithoutARealKey() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        await MeetingPreview.prepare(meeting, scenario: "live")
        #expect(!meeting.previewUsesLiveAI)
        #expect(try await meeting.credentials.store.read() == nil)
        #expect(meeting.insights.count == 2)
        meeting.setAIAllowed(true)
        await meeting.ai.ask("担当者は？")
        #expect(meeting.insights.last?.text.contains("架空の回答") == true)
        await meeting.end()
    }
}
