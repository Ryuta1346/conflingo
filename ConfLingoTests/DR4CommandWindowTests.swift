import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(2)))
    struct DR4CommandWindowTests {
        @Test func settingsAndSheetsCannotControlTheCapturingMeeting() async throws {
            let composition = AppComposition(arguments: ["--meeting-preview"])
            let meeting = composition.meeting
            meeting.consentConfirmed = true
            await meeting.start()
            let main = DR3Host(ContentView(composition: composition), width: 900, padding: 0, nonactivating: true)
            defer { main.close() }
            await main.layout()
            main.window.makeKeyAndOrderFront(nil)
            await main.layout()
            #expect(NSApp.keyWindow === main.window, "Key window: \(NSApp.keyWindow?.title ?? "none")")
            #expect(composition.commands.active?.session?.canToggle == true)
            let settings = DR3Host(AppSettingsView(composition: composition), width: 760, height: 720, padding: 0, nonactivating: true)
            await settings.layout()
            #expect(composition.commands.active == nil)
            #expect(meeting.phase == .listening)
            settings.close()
            main.window.makeKeyAndOrderFront(nil)
            await main.layout()
            let requestEnd = try #require(composition.commands.active?.session?.end)
            requestEnd()
            #expect(try await waitForTestCondition { main.window.attachedSheet != nil })
            #expect(meeting.page == .live)
            #expect(meeting.phase == .listening)
            #expect(composition.commands.active == nil)
            meeting.cancelEnd()
            #expect(try await waitForTestCondition { main.window.attachedSheet == nil })
            await meeting.end()
        }

        @Test func compactWindowMenuRequestsItsOwnEndConfirmation() async throws {
            let composition = AppComposition(arguments: ["--meeting-preview"])
            let meeting = composition.meeting
            meeting.consentConfirmed = true
            await meeting.start()
            let main = DR3Host(ContentView(composition: composition), width: 900, padding: 0, nonactivating: true)
            defer { composition.floatingPanel.hide(); main.close() }
            await main.layout()
            composition.floatingPanel.show(meeting: meeting, compactMain: true)
            let panel = try #require(composition.floatingPanel.panel)
            panel.makeKeyAndOrderFront(nil)
            #expect(try await waitForTestCondition { composition.commands.active?.session?.end != nil && NSApp.keyWindow === panel })
            let requestEnd = try #require(composition.commands.active?.session?.end)
            requestEnd()
            #expect(try await waitForTestCondition { panel.attachedSheet != nil })
            #expect(main.window.attachedSheet == nil)
            #expect(meeting.phase == .listening)
            meeting.cancelEnd()
            #expect(try await waitForTestCondition { panel.attachedSheet == nil })
            await meeting.end()
        }

        @Test func returnSavesConnectionAndEscapeCancelsWithoutSaving() async throws {
            let settings = conferenceTestSettings()
            let fixture = DR3Host(LLMSettingsView(settings: settings), width: 760, height: 720)
            defer { fixture.close() }
            await fixture.layout()
            func openEditor() async throws -> NSWindow {
                try #require(fixture.element("編集・APIキー設定")).perform(NSSelectorFromString("accessibilityPerformPress"))
                #expect(try await waitForTestCondition { fixture.window.attachedSheet != nil })
                await fixture.layout()
                return try #require(fixture.window.attachedSheet)
            }
            let revision = settings.revision
            let sheet = try await openEditor()
            sheet.makeKeyAndOrderFront(nil)
            let content = try #require(sheet.contentView)
            let name = try #require(fixture.elements(content).first {
                fixture.value("accessibilityRole", $0) as? String == "AXTextField"
                    && fixture.value("accessibilityValue", $0) as? String == settings.selected.name
            })
            name.setValue("DR4 connection", forKey: "accessibilityValue")
            sheet.makeFirstResponder(nil)
            try sendKey("\r", code: 36, to: sheet)
            #expect(try await waitForTestCondition { fixture.window.attachedSheet == nil })
            #expect(settings.revision > revision)
            #expect(settings.selected.name == "DR4 connection")
            let savedRevision = settings.revision
            let cancelSheet = try await openEditor()
            cancelSheet.makeKeyAndOrderFront(nil)
            try sendKey("\u{1B}", code: 53, to: cancelSheet)
            #expect(try await waitForTestCondition { fixture.window.attachedSheet == nil })
            #expect(settings.revision == savedRevision)
        }

        @Test func returnInQuestionComposerDoesNotSend() async throws {
            let composition = AppComposition(arguments: ["--ui-preview"])
            let workspace = composition.conferenceKnowledge
            workspace.setAssistancePermission(true)
            workspace.assistanceDraft = "送信せずに改行します"
            let fixture = DR3Host(ConferenceAssistanceView(workspace: workspace), width: 640, height: 720)
            defer { fixture.close() }
            await fixture.layout()
            let field = try #require(fixture.elements(fixture.host).first { fixture.value("accessibilityLabel", $0) as? String == "AIへの質問" })
            field.setValue(true, forKey: "accessibilityFocused")
            try sendKey("\r", code: 36, to: fixture.window)
            await fixture.layout()
            #expect(workspace.assistance.insights.isEmpty)
            #expect(workspace.assistanceDraft.contains("送信せずに改行します"))
        }

        @Test func sendingScopeOpensOneResearchConfirmationAfterClosingSettings() async throws {
            let composition = AppComposition(arguments: ["--ui-preview"])
            let workspace = composition.conferenceKnowledge
            let fixture = DR3Host(ConferenceAssistanceView(workspace: workspace), height: 720)
            defer { fixture.close() }
            await fixture.layout()
            try #require(fixture.element("AI設定 · オフ")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { fixture.window.attachedSheet != nil })
            let settings = try #require(fixture.window.attachedSheet)
            let content = try #require(settings.contentView)
            let open = try #require(fixture.elements(content).first {
                fixture.value("accessibilityLabel", $0) as? String == "Web調査の送信範囲を確認"
            })
            open.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition {
                workspace.research.showsSheet && fixture.window.attachedSheet != nil && fixture.window.attachedSheet !== settings
            })
            #expect(fixture.window.attachedSheet?.attachedSheet == nil)
            #expect(workspace.research.requestCount == 0)
            #expect(!workspace.research.permitted)
        }

        @Test func returnConfirmsMarkedTextWithoutSavingTheConnection() async throws {
            let settings = conferenceTestSettings()
            let fixture = DR3Host(LLMSettingsView(settings: settings), width: 760, height: 720, nonactivating: true)
            defer { fixture.close() }
            await fixture.layout()
            try #require(fixture.element("編集・APIキー設定")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { fixture.window.attachedSheet != nil })
            await fixture.layout()
            let sheet = try #require(fixture.window.attachedSheet)
            let content = try #require(sheet.contentView)
            let name = try #require(fixture.elements(content).first {
                fixture.value("accessibilityRole", $0) as? String == "AXTextField"
                    && fixture.value("accessibilityValue", $0) as? String == settings.selected.name
            })
            name.setValue(true, forKey: "accessibilityFocused")
            let editor = try #require(sheet.firstResponder as? NSTextView)
            editor.setMarkedText("へんかん", selectedRange: NSRange(location: 4, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0))
            #expect(editor.hasMarkedText())
            let revision = settings.revision
            try sendKey("\r", code: 36, to: sheet)
            await fixture.layout()
            #expect(fixture.window.attachedSheet === sheet)
            #expect(settings.revision == revision)
        }

        private func sendKey(_ text: String, code: UInt16, to window: NSWindow) throws {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: text, charactersIgnoringModifiers: text,
                isARepeat: false, keyCode: code))
            window.sendEvent(event)
        }
    }
}
