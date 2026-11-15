import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DR5PresentationTests {
        @Test func transcriptHasKeyboardMenuOnlyForFinalUtterances() async throws {
            let meeting = MeetingWorkspace(controller: DualFixture().controller())
            for final in [false, true] {
                meeting.store.receive(TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .microphone,
                    languageCode: "ja", startOffset: final ? 1 : 2, endOffset: 3, text: final ? "確定発話" : "途中の発話",
                    isFinal: final, revision: 1, sourceStartTime: 0))
            }
            let fixture = DR3Host(MeetingTranscriptView(meeting: meeting, fontSize: 16))
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.strings.filter { $0 == "00:00:01の発話の操作" }.count == 1)
            #expect(!fixture.strings.contains("00:00:02の発話の操作"))
            #expect(fixture.element("この発話をWebで調べる") == nil)
            let menu = try #require(fixture.elements(fixture.host).first {
                fixture.value("accessibilityLabel", $0) as? String == "00:00:01の発話の操作"
            })
            fixture.window.makeFirstResponder(nil)
            for _ in 0..<12 {
                fixture.window.selectNextKeyView(nil)
                await fixture.layout()
                if fixture.value("isAccessibilityFocused", menu) as? Bool == true { break }
            }
            #expect(fixture.value("isAccessibilityFocused", menu) as? Bool == true)
            let info = try #require(fixture.element("入力元の表示について"))
            info.perform(NSSelectorFromString("accessibilityPerformPress"))
            await fixture.layout()
            #expect(!meeting.research.showsSheet)
        }

        @Test(arguments: [640.0, 1280.0])
        func homeEntrancesKeepActionsAndAdaptColumns(width: Double) async throws {
            var actions: [String] = []
            let fixture = DR3Host(HomeView(hasTranscript: true, prepare: { actions.append("conference") },
                openTranscript: { actions.append("transcript") }, openMeeting: { actions.append("meeting") }),
                width: width, height: 1000, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            let conference = try #require(fixture.element("字幕を準備する"))
            let meeting = try #require(fixture.element("会議を開く"))
            let first = try frame(conference, fixture), second = try frame(meeting, fixture)
            if width > 1000 { #expect(abs(first.midY - second.midY) < 2) }
            else { #expect(first.midY > second.midY) }
            conference.perform(NSSelectorFromString("accessibilityPerformPress"))
            meeting.perform(NSSelectorFromString("accessibilityPerformPress"))
            try #require(fixture.element("字幕を開く")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(actions == ["conference", "meeting", "transcript"])
            try capture(fixture, name: "home-\(Int(width))")
        }

        @Test func savedRowMainAreaOpensAndDeleteRemainsSeparate() async throws {
            let entry = SessionListEntry(id: UUID(), title: "保存した会議", kind: "Meeting", startedAt: nil, updatedAt: nil, failure: nil)
            var opened = 0, deleted = 0
            let fixture = DR3Host(SavedSessionRow(entry: entry, open: { opened += 1 }, delete: { deleted += 1 }))
            defer { fixture.close() }
            await fixture.layout()
            let open = try #require(fixture.element("保存した会議を開く"))
            #expect(try frame(open, fixture).width > 400)
            #expect(try frame(open, fixture).height > 55)
            open.perform(NSSelectorFromString("accessibilityPerformPress"))
            try #require(fixture.element("保存した会議を削除")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(opened == 1 && deleted == 1)
        }

        @Test func libraryTechnicalDetailsStartCollapsedAndRemainAvailable() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let files = KnowledgeLibraryFiles(directory: root)
            let saved = try await files.save(try await libraryArchive("資料の本文です。"), title: "資料の仕様")
            let library = KnowledgeLibrary(files: files)
            let fixture = DR3Host(KnowledgeLibraryView(library: library, fontSize: 32), height: 700, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            await library.open(saved.id)
            await fixture.layout()
            #expect(!fixture.strings.contains { $0.contains("保存版 ") })
            let details = try #require(fixture.element("技術情報"))
            details.perform(NSSelectorFromString("accessibilityPerformPress"))
            await fixture.layout()
            #expect(fixture.strings.contains { $0.contains(saved.revision.uuidString) })
            #expect(fixture.strings.contains { $0.contains("資料の本文です。") })
        }

        private func frame(_ element: NSObject, _ fixture: DR3Host) throws -> NSRect {
            try #require(fixture.value("accessibilityFrame", element) as? NSValue).rectValue
        }

        private func capture(_ fixture: DR3Host, name: String) throws {
            let bitmap = try #require(fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds))
            fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr5-\(name).png"))
        }
    }
}
