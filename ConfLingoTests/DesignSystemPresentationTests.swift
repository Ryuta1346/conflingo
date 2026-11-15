import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DesignSystemPresentationTests {
        @Test func replacingAMessageCollapsesOldDetails() async throws {
            let state = NoticeFixture()
            let fixture = DR3Host(NoticeFixtureView(state: state))
            defer { fixture.close() }
            await fixture.layout()
            try #require(fixture.element("詳細")).perform(NSSelectorFromString("accessibilityPerformPress"))
            await fixture.layout()
            #expect(fixture.strings.contains { $0.contains("first diagnostic") })
            state.notice = UserMessage(.failure, "別の操作が失敗しました。", details: "second diagnostic")
            await fixture.layout()
            #expect(!fixture.strings.contains { $0.contains("diagnostic") })
            state.notice = UserMessage(.success, "保存しました。")
            await fixture.layout()
            #expect(fixture.element("詳細") == nil)
            #expect(fixture.strings.contains { $0.contains("保存しました") })
        }

        @Test func cancellationDuringLibraryAttachIsInformation() async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let library = KnowledgeLibrary(files: KnowledgeLibraryFiles(directory: directory), load: { _ in throw CancellationError() })
            #expect(await !library.attach(UUID(), to: KnowledgeStore()))
            #expect(library.failure?.kind == .information)
            #expect(library.failure?.details == nil)
        }

        @Test(arguments: [false, true])
        func captureComponentsAndSendingExplanation(dark: Bool) async throws {
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            let fixture = DR3Host(ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("操作と処理結果").font(DesignTokens.Typography.title)
                    HStack {
                        Button("質問する") {}.buttonStyle(AppButtonStyle(.primary))
                        Button("書き出す") {}.buttonStyle(AppButtonStyle())
                        Button("削除", role: .destructive) {}.buttonStyle(AppButtonStyle())
                        Button("根拠を見る") {}.buttonStyle(AppButtonStyle(.link))
                    }
                    HStack {
                        Button("質問する") {}.buttonStyle(AppButtonStyle(.primary)).disabled(true)
                        Text("未入力のため送信できません").font(DesignTokens.Typography.supporting)
                    }
                    InlineMessage(.information, "音声はこのMacで処理します。")
                    InlineMessage(.success, "資料を取り込みました。")
                    InlineMessage(.warning, "保存後に変更があります。再保存してください。")
                    InlineMessage(.failure, "保存に失敗しました。現在の内容は保持しています。", details: "The file could not be opened.")
                    MeetingAISettings(meeting: meeting)
                }.padding(1)
            }
            .background(DesignTokens.canvas).foregroundStyle(DesignTokens.text)
            .buttonStyle(AppButtonStyle()).font(DesignTokens.Typography.body)
            .environment(\.colorScheme, dark ? .dark : .light), height: 1100)
            defer { fixture.close() }
            fixture.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            await fixture.layout()
            #expect(fixture.strings.contains { $0.contains("最大30件送ります") })
            #expect(fixture.strings.contains { $0.contains("最大5箇所・6,000文字") })
            #expect(!meeting.ai.permitted)
            try capture(fixture, name: "components-\(dark ? "dark" : "light")")
        }

        @Test func settingsSheetClosesFromHeaderWithoutSending() async throws {
            let suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = LLMSettings(defaults: defaults, keyStore: { _ in PresentationKeyStore() })
            var closed = false
            let fixture = DR3Host(LLMSettingsSheet(settings: settings, close: { closed = true }), width: 640, height: 520, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            let close = try #require(fixture.element("閉じる"))
            let frame = try #require(fixture.value("accessibilityFrame", close) as? NSValue).rectValue
            let windowFrame = fixture.window.frame
            #expect(frame.midX > windowFrame.midX)
            #expect(frame.midY > windowFrame.midY)
            #expect(fixture.host.frame.width <= 640)
            #expect(fixture.host.frame.height <= 520)
            #expect(frame.maxX <= windowFrame.maxX)
            #expect(frame.minY >= windowFrame.minY)
            try capture(fixture, name: "llm-settings-640")
            close.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(closed)
            #expect(settings.revision == 0)
        }

        @Test(arguments: [16.0, 48.0])
        func lowConferenceRevealsClearButtonWhenFocused(fontSize: Double) async throws {
            try #require(NSApp.isFullKeyboardAccessEnabled)
            let suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(fontSize, forKey: "fontSize")
            let composition = AppComposition(arguments: ["--ui-preview"], defaults: defaults)
            composition.store.mode = .translation
            let fixture = DR3Host(ContentView(composition: composition), width: 640, height: 520, padding: 0)
            defer { fixture.close() }
            await fixture.layout()
            let clear = try #require(fixture.element("字幕を消去"))
            try #require(clear.responds(to: NSSelectorFromString("setAccessibilityFocused:")))
            clear.setValue(true, forKey: "accessibilityFocused")
            await fixture.layout()
            let resume = try #require(fixture.element("字幕を再開"))
            let clearFrame = try #require(fixture.value("accessibilityFrame", clear) as? NSValue).rectValue
            let resumeFrame = try #require(fixture.value("accessibilityFrame", resume) as? NSValue).rectValue
            #expect(clearFrame.minY > resumeFrame.maxY)
            #expect(clearFrame.maxY < fixture.window.frame.maxY)
            try capture(fixture, name: "conference-focused-\(Int(fontSize))")
        }

        private func capture(_ fixture: DR3Host, name: String) throws {
            let bitmap = try #require(fixture.host.bitmapImageRepForCachingDisplay(in: fixture.host.bounds))
            fixture.host.cacheDisplay(in: fixture.host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr3-\(name).png"))
        }
    }
}

@MainActor @Observable private final class NoticeFixture {
    var notice = UserMessage(.failure, "最初の操作が失敗しました。", details: "first diagnostic")
}

private struct NoticeFixtureView: View {
    let state: NoticeFixture
    var body: some View { InlineMessage(state.notice) }
}

@MainActor private struct PresentationKeyStore: APIKeyStore {
    func read() async throws -> String? { nil }
    func save(_ key: String) throws {}
    func delete() throws {}
}
