import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AudioFailurePresentationTests {
    @Test func systemDiagnosticIsCollapsedAndRetryClearsIt() async throws {
        let input = DualFixture()
        let dual = input.controller()
        let conference = SessionController(dualController: dual)
        await dual.start()
        input.microphone.fail(NSError(domain: "AudioTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Synthetic audio diagnostic"]))
        await dual.stop()
        let message = try #require(conference.failure)
        #expect(message.kind == .failure)
        #expect(message.details == "Synthetic audio diagnostic")
        #expect(!message.text.contains("Synthetic"))
        let host = DR3Host(InlineMessage(message))
        defer { host.close() }
        await host.layout()
        #expect(!host.strings.contains { $0.contains("Synthetic") })
        try #require(host.element("詳細")).perform(NSSelectorFromString("accessibilityPerformPress"))
        await host.layout()
        #expect(host.strings.contains { $0.contains("Synthetic audio diagnostic") })
        await dual.start()
        #expect(conference.failure == nil)
        await dual.stop()
    }

    @Test(arguments: ["permission", "overflow", "configuration"])
    func recoveryGuidanceIsVisibleWithoutOpeningDetails(scenario: String) async throws {
        let input = DualFixture()
        let meeting = MeetingWorkspace(controller: input.controller(), llmSettings: conferenceTestSettings())
        meeting.consentConfirmed = true
        if scenario == "permission" { input.microphonePermission.status = .denied }
        await meeting.start()
        let expected: String
        switch scenario {
        case "permission": expected = "システム設定 > プライバシーとセキュリティ > マイク"
        case "overflow":
            input.microphone.fail(TranscriptEventHub.Failure.overflow)
            await meeting.controller.stop()
            expected = "最後の発話が欠けている可能性"
        default:
            input.microphone.fail(AudioCaptureError.configurationChanged)
            await meeting.controller.stop()
            expected = "入力機器を確認して、もう一度開始"
        }
        #expect(meeting.controller.lastError?.contains(expected) == true)
        let host = DR3Host(MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}), height: 1000)
        defer { host.close() }
        await host.layout()
        #expect(host.strings.contains { $0.contains(expected) })

        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let floating = MeetingFloatingPanel(defaults: defaults)
        floating.show(meeting: meeting)
        defer { floating.panel?.close() }
        await host.layout()
        let panelContent = try #require(floating.panel?.contentView)
        let strings = host.elements(panelContent).flatMap { object in
            ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { host.value($0, object) as? String }
        }
        #expect(strings.contains { $0.contains(expected) })
        await meeting.controller.stop()
    }
}
