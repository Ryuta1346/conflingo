import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized)
    struct DR4PreparationTests {
        @Test(arguments: AudioInputSelection.allCases)
        func preparationShowsOnlySelectedInputs(input: AudioInputSelection) async throws {
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.inputSelection = input
            meeting.mode = .translation
            let fixture = DR3Host(MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}), height: 1800)
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.strings.contains("会議名"))
            #expect(fixture.strings.contains("マイク・外部入力の認識言語") == input.origins.contains(.microphone))
            #expect(fixture.strings.contains("内部音声の認識言語") == input.origins.contains(.systemAudio))
            #expect(fixture.strings.contains("参加者への通知と同意を確認してください。"))
            meeting.consentConfirmed = true
            await fixture.layout()
            #expect(!fixture.strings.contains("参加者への通知と同意を確認してください。"))
            #expect(meeting.canStart)
        }

        @Test func changingInputsPreservesHiddenLanguageChoices() async throws {
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.microphoneLocaleID = "fr-FR"
            meeting.systemLocaleID = "de-DE"
            let fixture = DR3Host(MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}), height: 1600)
            defer { fixture.close() }
            for input in AudioInputSelection.allCases {
                meeting.inputSelection = input
                await fixture.layout()
                #expect(meeting.microphoneLocaleID == "fr-FR")
                #expect(meeting.systemLocaleID == "de-DE")
            }
        }
    }
}

extension AppKitIntegrationTests.DR4PreparationTests {
    @Test func equivalentLocaleSpellingIsNotReportedAsUnsupported() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        meeting.inputSelection = .microphone
        meeting.microphoneLocaleID = "en_US"
        let fixture = DR3Host(MeetingPreparationForm(meeting: meeting, models: PreparationStub()), height: 900)
        defer { fixture.close() }
        await fixture.layout()
        #expect(!fixture.strings.contains { $0.contains("対応一覧にありません") })
        meeting.microphoneLocaleID = "zz-ZZ"
        await fixture.layout()
        #expect(fixture.strings.contains { $0.contains("対応一覧にありません") })
    }
}

extension AppKitIntegrationTests.DR4PreparationTests {
    @Test func recognitionModeReloadsItsOwnSupportedLanguages() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        let vocabulary = PreparationStub(heldStage: .sources)
        let fixture = DR3Host(MeetingPreparationForm(meeting: meeting, models: PreparationStub(), vocabularyModels: vocabulary), height: 900)
        defer { fixture.close(); vocabulary.gate.release() }
        await fixture.layout()
        #expect(vocabulary.heldStage == .sources)
        meeting.recognitionMode = .vocabulary
        #expect(try await waitForTestCondition { vocabulary.heldStage == nil })
        vocabulary.gate.release()
        await fixture.layout()
    }

    @Test func readOnlyDictionaryKeepsCloseAvailable() async throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let fixture = DR3Host(KeywordProfileEditor(profiles: KeywordProfileStore(defaults: defaults), canEdit: false))
        defer { fixture.close() }
        await fixture.layout()
        let close = try #require(fixture.element("閉じる"))
        let create = try #require(fixture.element("新規作成"))
        #expect(fixture.value("isAccessibilityEnabled", close) as? Bool == true)
        #expect(fixture.value("isAccessibilityEnabled", create) as? Bool == false)
    }
}
