import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DR4PresentationTests {
        @Test(arguments: [640.0, 1280.0], [false, true])
        func capturePreparationAndSendingScopes(width: Double, dark: Bool) async throws {
            let composition = AppComposition(arguments: ["--meeting-preview"])
            composition.meeting.inputSelection = .microphone
            composition.meeting.microphoneLocaleID = "en-US"
            let preparation = DR3Host(ScrollView {
                MeetingPreparationForm(meeting: composition.meeting, models: PreparationStub()).padding(24)
            }.background(DesignTokens.canvas).foregroundStyle(DesignTokens.text)
                .environment(\.colorScheme, dark ? .dark : .light), width: width, height: 800, padding: 0)
            await preparation.layout()
            try capture(preparation, name: "preparation-\(Int(width))-\(dark ? "dark" : "light")")
            preparation.close()
            let scopes = DR3Host(ConferenceAssistanceSettings(workspace: composition.conferenceKnowledge)
                .environment(\.colorScheme, dark ? .dark : .light), width: width, height: 1000, padding: 0)
            defer { scopes.close() }
            await scopes.layout()
            #expect(scopes.strings.contains("資料だけの質問を許可"))
            #expect(!composition.conferenceKnowledge.questionPermitted)
            try capture(scopes, name: "sending-\(Int(width))-\(dark ? "dark" : "light")")
        }

        @Test(arguments: [16.0, 32.0, 48.0])
        func captureConferenceAnswerAndCorrectionEntry(fontSize: Double) async throws {
            let suite = "DR4.Capture." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(fontSize, forKey: "fontSize")
            let composition = AppComposition(arguments: ["--ui-preview"], defaults: defaults)
            composition.conferenceKnowledge.assistanceVisible = true
            let fixture = DR3Host(ContentView(composition: composition), width: 1280, height: 800, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.element("この発話を資料で補正") != nil)
            try capture(fixture, name: "conference-\(Int(fontSize))")
            try #require(fixture.element("この発話を資料で補正")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { fixture.window.attachedSheet != nil })
            let sheet = try #require(fixture.window.attachedSheet)
            let content = try #require(sheet.contentView)
            content.layoutSubtreeIfNeeded()
            #expect(fixture.elements(content).contains { fixture.value("accessibilityLabel", $0) as? String == "資料で補正する" })
            #expect(!composition.conferenceKnowledge.correctionPermitted)
        }

        private func capture(_ fixture: DR3Host, name: String) throws {
            let bitmap = try #require(fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds))
            fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr4-\(name).png"))
        }
    }
}
