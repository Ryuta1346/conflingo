import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DR5InteractionTests {
        @Test func utteranceActionSelectsExactEvidenceWithoutSending() async throws {
            let meeting = MeetingWorkspace(controller: DualFixture().controller())
            let event = TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .systemAudio,
                languageCode: "en", startOffset: 12, endOffset: 13, text: "Which release is affected?",
                isFinal: true, revision: 1, sourceStartTime: 12)
            meeting.store.receive(event)
            let fixture = DR3Host(MeetingUtteranceActions(meeting: meeting, event: event))
            defer { fixture.close() }
            await fixture.layout()
            try #require(fixture.element("この発話をWebで調べる")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(meeting.research.showsSheet)
            #expect(meeting.research.draftQuery == event.text)
            #expect(meeting.research.selectedEvidenceIDs == [event.id])
            #expect(!meeting.research.permitted && meeting.research.requestCount == 0)
            meeting.research.showsSheet = false
            await meeting.end()
            await fixture.layout()
            #expect(fixture.element("この発話をWebで調べる") == nil)
        }

        @Test func twoTransportViewsDoNotDuplicateStateAnnouncements() async throws {
            var announcements: [String] = []
            let meeting = MeetingWorkspace(controller: DualFixture().controller(), announceStatus: { announcements.append($0) })
            let main = DR3Host(MeetingTransport(meeting: meeting), width: 900, height: 260)
            let small = DR3Host(MeetingTransport(meeting: meeting), width: 360, height: 300)
            defer { main.close(); small.close() }
            await main.layout()
            await small.layout()
            #expect(announcements.isEmpty)
            meeting.inputSelection = .microphone
            meeting.consentConfirmed = true
            await meeting.start()
            await main.layout()
            await small.layout()
            #expect(announcements.filter { $0 == "会議：取得中" }.count == 1)
            #expect(!small.strings.contains { $0.contains("内部音声") })
            #expect(small.strings.contains { $0.contains("開始から") })
            await meeting.pause()
            await small.layout()
            #expect(announcements.filter { $0 == "会議：一時停止" }.count == 1)
            let resume = try #require(small.element("再開"))
            #expect(try #require(small.value("accessibilityFrame", resume) as? NSValue).rectValue.maxX <= small.window.frame.maxX)
        }

        @Test func libraryOpenAreaAndSelectionKeepIndependentActions() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let files = KnowledgeLibraryFiles(directory: root)
            let saved = try await files.save(try await libraryArchive("選択と閲覧の検証資料"), title: "会議の資料")
            let library = KnowledgeLibrary(files: files)
            var selected: [UUID] = []
            let fixture = DR3Host(KnowledgeLibraryView(library: library, fontSize: 16, attachedIDs: [saved.id],
                choose: { selected.append($0.id) }), height: 700, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            let add = try #require(fixture.element("会議の資料を追加"))
            #expect(fixture.value("isAccessibilityEnabled", add) as? Bool == false)
            add.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(selected.isEmpty)
            let open = try #require(fixture.element("会議の資料を開く"))
            #expect(try #require(fixture.value("accessibilityFrame", open) as? NSValue).rectValue.width > 400)
            open.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { library.selected?.id == saved.id })
            await fixture.layout()
            try #require(fixture.element("一覧へ戻る")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(library.selected == nil && selected.isEmpty)
        }

        @Test(arguments: [640.0, 900.0, 1280.0, 1512.0], [false, true])
        func homeAndMeetingRenderAtSupportedWidths(width: Double, dark: Bool) async throws {
            let home = DR3Host(HomeView(hasTranscript: true, prepare: {}, openTranscript: {}, openMeeting: {})
                .background(DesignTokens.canvas).foregroundStyle(DesignTokens.text)
                .environment(\.colorScheme, dark ? .dark : .light), width: width, height: 800, padding: 0)
            home.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            await home.layout()
            try capture(home, "home-\(Int(width))-\(dark ? "dark" : "light")")
            home.close()
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.consentConfirmed = true
            await meeting.start()
            MeetingPreview.populate(meeting, count: 4)
            let live = DR3Host(MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {})
                .background(DesignTokens.canvas).foregroundStyle(DesignTokens.text).buttonStyle(AppButtonStyle())
                .environment(\.colorScheme, dark ? .dark : .light), width: width, height: 800, padding: 0)
            defer { live.close() }
            live.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            await live.layout()
            #expect(live.element("一時停止") != nil)
            #expect(live.strings.contains { $0.contains("開始から") })
            try capture(live, "meeting-\(Int(width))-\(dark ? "dark" : "light")")
            await meeting.pause()
        }

        @Test(arguments: [16.0, 32.0, 48.0])
        func largeTranscriptAndSmallWindowKeepControls(fontSize: Double) async throws {
            let suite = "DR5.Capture." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(fontSize, forKey: "fontSize")
            let meeting = MeetingPreview.make(activity: AudioInputUse(), defaults: defaults)
            meeting.consentConfirmed = true
            await meeting.start()
            MeetingPreview.populate(meeting, count: 2)
            let live = DR3Host(MeetingTranscriptView(meeting: meeting, fontSize: fontSize), width: 640, height: 520)
            await live.layout()
            try capture(live, "transcript-\(Int(fontSize))")
            let floating = MeetingFloatingPanel(defaults: defaults)
            floating.show(meeting: meeting)
            let panel = try #require(floating.panel)
            defer { panel.close(); live.close() }
            panel.setContentSize(NSSize(width: 360, height: 430))
            let content = try #require(panel.contentView)
            await live.layout()
            content.layoutSubtreeIfNeeded()
            let end = try #require(live.elements(content).first { live.value("accessibilityLabel", $0) as? String == "会議を終了" })
            let frame = try #require(live.value("accessibilityFrame", end) as? NSValue).rectValue
            #expect(panel.frame.contains(frame))
            try captureView(content, "small-\(Int(fontSize))")
            await meeting.pause()
        }

        private func capture(_ fixture: DR3Host, _ name: String) throws {
            try captureView(fixture.host, name)
        }

        private func captureView(_ host: NSView, _ name: String) throws {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr5-\(name).png"))
        }
    }
}
