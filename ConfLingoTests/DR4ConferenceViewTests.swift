import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized)
    struct DR4ConferenceViewTests {
        @Test func documentSheetContainsOnlyMaterialsAndTerms() async throws {
            let composition = AppComposition(arguments: ["--ui-preview"])
            let fixture = DR3Host(ConferenceKnowledgeView(workspace: composition.conferenceKnowledge,
                library: composition.library, fontSize: 16,
                sourceLanguage: "en-US", targetLanguage: nil, applyTerms: {}), height: 1500)
            defer { fixture.close() }
            await fixture.layout()
            #expect(!fixture.strings.contains("資料だけに質問"))
            #expect(fixture.element("このMacに保存") == nil)
            #expect(fixture.element("質問する") == nil)
            #expect(fixture.element("LLM設定") == nil)
        }

        @Test func sharedSettingsKeepManualAndAutomaticConsentSeparate() async throws {
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            let fixture = DR3Host(MeetingAISettings(meeting: meeting), height: 1800)
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.element("手動質問にも資料を使う") != nil)
            #expect(!meeting.ai.permitted)
            #expect(!meeting.knowledge.permitted)
            #expect(!meeting.ai.automaticEnabled)
        }
    }
}
