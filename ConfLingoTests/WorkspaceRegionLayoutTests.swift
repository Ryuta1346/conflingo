import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(2)))
    struct WorkspaceRegionLayoutTests {
        @Test(arguments: [820.0, 831.0, 832.0, 899.0, 900.0, 1023.0, 1024.0, 1180.0, 1185.0, 1280.0, 1345.0, 1346.0, 1512.0])
        func conferencePrioritizesTwoSubtitleColumns(width: Double) async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let composition = AppComposition(arguments: ["--ui-preview"])
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: width)
            defer { window.close() }
            await layout(host)
            let source = try #require(element(in: host, labelPrefix: "原文 ·"))
            let translation = try #require(element(in: host, labelPrefix: "翻訳 ·"))
            let sourceFrame = frame(source)
            let translationFrame = frame(translation)
            #expect(abs(sourceFrame.midY - translationFrame.midY) < 4, "Subtitle headers must remain side by side at \(width)")
            #expect(translationFrame.minX > sourceFrame.minX + 200)
        }

        @Test func conferenceSaveLivesBesideExportAndSupportCanBeOpenedAtNarrowWidth() async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let composition = AppComposition(arguments: ["--ui-preview"])
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: 640)
            defer { window.close() }
            await layout(host)
            let save = try #require(button(in: host, title: "このMacに保存"))
            let export = try #require(button(in: host, title: "書き出す"))
            #expect(abs(frame(save).midY - frame(export).midY) < 4)
            let open = try #require(button(in: host, title: "AI支援を開く"))
            open.perform(NSSelectorFromString("accessibilityPerformPress"))
            await layout(host)
            #expect(button(in: host, title: "AI支援を閉じる") != nil)
        }

        @Test(arguments: [640.0, 1280.0])
        func liveMeetingStartsWithAnswersInsteadOfSettings(width: Double) async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.consentConfirmed = true
            await meeting.start()
            MeetingPreview.populate(meeting)
            let host = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}))
            let window = window(host, width: width)
            defer { window.close() }
            await layout(host)
            #expect(element(in: host, labelPrefix: "AIの回答言語") == nil, "Settings are opened explicitly during Live")
            #expect(button(in: host, title: "AI設定 · オフ") != nil)
            let answer = try #require(element(in: host, labelPrefix: "レビューの担当者は決まっていますか？"))
            #expect(frame(answer).intersects(window.convertToScreen(host.visibleRect)), "The newest answer must be visible initially")
            await meeting.end()
        }

        @Test func conferenceKeepsDraftAndAnswersAcrossSidebarAndOverlay() async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let composition = AppComposition(arguments: ["--ui-preview"])
            let workspace = composition.conferenceKnowledge
            workspace.setAssistancePermission(true)
            await workspace.askAssistance("What should we confirm?")
            let answers = workspace.assistance.insights.map(\.id)
            try #require(!answers.isEmpty)
            let sessionID = composition.store.sessionID
            workspace.assistanceDraft = "Keep this question while resizing"
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: 1512)
            defer { window.close() }
            for width in [1512.0, 900.0, 640.0, 1280.0, 1512.0] {
                workspace.assistanceVisible = false
                window.setContentSize(NSSize(width: width, height: 800))
                await layout(host)
                let open = try #require(button(in: host, title: "AI支援を開く"))
                open.perform(NSSelectorFromString("accessibilityPerformPress"))
                await layout(host)
                let question = try #require(element(in: host, labelPrefix: "AIへの質問"))
                #expect(value("accessibilityValue", question) as? String == workspace.assistanceDraft)
                #expect(workspace.assistance.insights.map(\.id) == answers)
                #expect(composition.store.sessionID == sessionID)
            }
            let stop = try #require(button(in: host, title: "AI送信を停止"))
            stop.perform(NSSelectorFromString("accessibilityPerformPress"))
            await layout(host)
            #expect(!workspace.assistance.permitted)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "質問する"))) as? Bool == false)
            #expect(workspace.assistanceDraft == "Keep this question while resizing")
            workspace.reset()
            #expect(workspace.assistanceDraft.isEmpty)
            #expect(workspace.assistanceVisible == nil)
        }

        @Test func meetingQuestionFollowsWorkspaceAcrossPreparationAndLive() async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.assistanceDraft = "Keep the draft"
            let preparation = NSHostingView(rootView: MeetingAIControls(meeting: meeting))
            let preparationWindow = window(preparation, width: 640)
            await layout(preparation)
            let input = try #require(element(in: preparation, labelPrefix: "AIへの質問"))
            #expect(value("accessibilityValue", input) as? String == "Keep the draft")
            preparationWindow.close()
            meeting.consentConfirmed = true
            await meeting.start()
            let live = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}))
            let liveWindow = window(live, width: 900)
            defer { liveWindow.close() }
            await layout(live)
            #expect(value("accessibilityValue", try #require(element(in: live, labelPrefix: "AIへの質問"))) as? String == "Keep the draft")
            await meeting.end()
            meeting.requestDiscard()
            meeting.confirmDiscard()
            #expect(meeting.assistanceDraft.isEmpty)
        }

        @Test(arguments: [640.0, 900.0, 1180.0, 1280.0, 1512.0], [false, true])
        func captureApprovedWidths(width: Double, isMeeting: Bool) async throws {
            let suite = "DR2.Capture." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("en-US", forKey: "sourceLocaleID")
            defaults.set("ja", forKey: "targetLanguageID")
            let composition = AppComposition(arguments: [isMeeting ? "--meeting-preview" : "--ui-preview"], defaults: defaults)
            composition.store.mode = .translation
            if isMeeting {
                composition.meeting.consentConfirmed = true
                await composition.meeting.start()
                MeetingPreview.populate(composition.meeting, count: 40, includeCandidates: true)
            }
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: width)
            defer { window.close() }
            for theme in ["light", "dark"] {
                defaults.set(theme, forKey: "appearance")
                await layout(host)
                #expect(host.frame.width <= width + 1)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr2-after-\(isMeeting ? "meeting" : "conference")-\(Int(width))-\(theme).png"))
            }
            if isMeeting { await composition.meeting.end() }
        }

        @Test func toolbarSavePreservesEligibilityAndResaveBehavior() async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("DR2.Save." + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = SessionsLibrary(files: SessionFiles(directory: root))
            let store = SessionStore()
            let host = NSHostingView(rootView: SaveFixture(store: store, library: library))
            let window = window(host, width: 640, height: 200)
            defer { window.close() }
            await layout(host)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "このMacに保存"))) as? Bool == false)
            _ = store.appendFinal("A completed sentence")
            store.phase = .listening
            await layout(host)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "このMacに保存"))) as? Bool == false)
            #expect(element(in: host, labelPrefix: "保存状態：停止後に保存") != nil)
            store.phase = .idle
            await layout(host)
            let save = try #require(button(in: host, title: "このMacに保存"))
            #expect(value("isAccessibilityEnabled", save) as? Bool == true)
            save.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { library.savedSnapshots[store.sessionID] != nil })
            await layout(host)
            #expect(element(in: host, labelPrefix: "保存状態：保存済み") != nil)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "変更を再保存"))) as? Bool == false)
            _ = store.appendFinal("A new sentence after saving")
            await layout(host)
            #expect(element(in: host, labelPrefix: "保存状態：変更あり") != nil)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "変更を再保存"))) as? Bool == true)
        }

        @Test func toolbarSaveFailureExposesDetailsAndAllowsRetry() async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("DR2.SaveFailure." + UUID().uuidString)
            try Data("not a directory".utf8).write(to: root)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = SessionsLibrary(files: SessionFiles(directory: root))
            let store = SessionStore()
            _ = store.appendFinal("Keep this after save failure")
            let host = NSHostingView(rootView: SaveFixture(store: store, library: library))
            let window = window(host, width: 640, height: 200)
            defer { window.close() }
            await layout(host)
            try #require(button(in: host, title: "このMacに保存")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { library.error != nil })
            await layout(host)
            let details = try #require(button(in: host, title: "保存状態：保存エラー。詳細を表示"))
            #expect(value("isAccessibilityEnabled", details) as? Bool == true)
            #expect(value("isAccessibilityEnabled", try #require(button(in: host, title: "このMacに保存"))) as? Bool == true)
            #expect(store.segments.first?.english == "Keep this after save failure")
            #expect(library.savedSnapshots.isEmpty)
            try FileManager.default.removeItem(at: root)
            try #require(button(in: host, title: "このMacに保存")).perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { library.savedSnapshots[store.sessionID] != nil })
            #expect(library.error == nil)
        }

        @Test func meetingSettingsCloseRestoresFocusWithoutSending() async throws {
            try #require(NSApp.isFullKeyboardAccessEnabled,
                "Button focus restoration requires System Settings > Keyboard > Keyboard navigation")
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.consentConfirmed = true
            await meeting.start()
            let host = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}))
            let window = window(host, width: 900)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            await layout(host)
            let open = try #require(button(in: host, title: "AI設定 · オフ"))
            open.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { window.attachedSheet != nil })
            let sheet = try #require(window.attachedSheet)
            let content = try #require(sheet.contentView)
            await layout(content)
            #expect(element(in: content, labelPrefix: "AIの回答言語") != nil)
            let close = try #require(button(in: content, title: "閉じる"))
            close.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(try await waitForTestCondition { window.attachedSheet == nil })
            await layout(host)
            #expect(try await waitForTestCondition {
                guard let target = button(in: host, title: "AI設定 · オフ") else { return false }
                return value("isAccessibilityFocused", target) as? Bool == true
            })
            #expect(!meeting.ai.permitted)
            #expect(meeting.insights.isEmpty)
            #expect(meeting.phase == .listening)
            await meeting.end()
        }

        @Test(arguments: [16.0, 32.0, 48.0])
        func lowMeetingWindowRevealsComposerWhenFocused(fontSize: Double) async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let suite = "DR2.Large." + UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(fontSize, forKey: "fontSize")
            defaults.set("light", forKey: "appearance")
            let composition = AppComposition(arguments: ["--meeting-preview"], defaults: defaults)
            let meeting = composition.meeting
            meeting.consentConfirmed = true
            await meeting.start()
            MeetingPreview.populate(meeting, includeCandidates: true)
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: 640, height: 520)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            await layout(host)
            let input = try #require(element(in: host, labelPrefix: "AIへの質問"))
            try #require(input.responds(to: NSSelectorFromString("setAccessibilityFocused:")))
            input.setValue(true, forKey: "accessibilityFocused")
            await layout(host)
            let pause = try #require(button(in: host, title: "一時停止"))
            #expect(frame(input).minY > frame(pause).maxY, "The focused question must be above the fixed transport, not clipped underneath it")
            #expect(frame(input).maxY < window.frame.maxY)
            #expect(host.frame.width <= 641)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr2-low-meeting-\(Int(fontSize)).png"))
            await meeting.end()
        }

        @Test func conferenceOverlayClosesWithEscapeAndRestoresToolbarFocus() async throws {
            try #require(NSApp.isFullKeyboardAccessEnabled,
                "Button focus restoration requires System Settings > Keyboard > Keyboard navigation")
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let composition = AppComposition(arguments: ["--ui-preview"])
            let host = NSHostingView(rootView: ContentView(composition: composition))
            let window = window(host, width: 900)
            window.makeKeyAndOrderFront(nil)
            defer { window.close() }
            await layout(host)
            try #require(button(in: host, title: "AI支援を開く")).perform(NSSelectorFromString("accessibilityPerformPress"))
            await layout(host)
            let input = try #require(element(in: host, labelPrefix: "AIへの質問"))
            input.setValue(true, forKey: "accessibilityFocused")
            let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
            window.sendEvent(escape)
            await layout(host)
            #expect(button(in: host, title: "AI支援を閉じる") == nil)
            #expect(try await waitForTestCondition {
                guard let target = button(in: host, title: "AI支援を開く") else { return false }
                return value("isAccessibilityFocused", target) as? Bool == true
            })
        }

        @Test(arguments: ["empty", "generating", "long"])
        func liveResultsKeepComposerOutsideScrollableContent(state: String) async throws {
            let release = TestAccessibility.shared.enable()
            defer { release() }
            let meeting = MeetingPreview.make(activity: AudioInputUse())
            meeting.consentConfirmed = true
            await meeting.start()
            if state != "empty" {
                meeting.insights = [MeetingInsight(kind: .answerSuggestion,
                    text: state == "long" ? String(repeating: "長い回答も本文だけをスクロールして確認できます。", count: 80) : "回答を生成しています。",
                    priority: 1, evidenceIDs: [], status: state == "generating" ? .generating : .complete)]
            }
            let host = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(32), compact: {})
                .background(DesignTokens.canvas).foregroundStyle(DesignTokens.text).preferredColorScheme(.light))
            let window = window(host, width: 900, height: 700)
            defer { window.close() }
            await layout(host)
            let input = try #require(element(in: host, labelPrefix: "AIへの質問"))
            let inputFrame = frame(input)
            #expect(inputFrame.minY > frame(try #require(button(in: host, title: "一時停止"))).maxY)
            if state == "empty" { #expect(element(in: host, labelPrefix: "提案はまだありません") != nil) }
            if state == "generating" { #expect(element(in: host, labelPrefix: "生成中・未検証") != nil) }
            let scrolls = descendants(host).compactMap { $0 as? NSScrollView }
            let results = try #require(scrolls.first { scroll in
                guard let document = scroll.documentView else { return false }
                return descendants(document).compactMap { $0 as? NSScrollView }.isEmpty &&
                    window.convertToScreen(scroll.convert(scroll.bounds, to: nil)).minX > 350
            })
            results.contentView.scroll(to: NSPoint(x: 0, y: max(0, (results.documentView?.frame.height ?? 0) - results.contentSize.height)))
            results.reflectScrolledClipView(results.contentView)
            await layout(host)
            #expect(abs(frame(input).minY - inputFrame.minY) < 2, "Scrolling answers must not move the composer")
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-dr2-state-\(state).png"))
            await meeting.end()
        }

        private func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }

        private struct SaveFixture: View {
            @Bindable var store: SessionStore
            let library: SessionsLibrary
            var body: some View {
                SessionSaveControls(library: library, snapshot: store.sessionSnapshot(sourceLanguage: "en-US", targetLanguage: nil), save: {
                    guard let snapshot = store.sessionSnapshot(sourceLanguage: "en-US", targetLanguage: nil) else { return }
                    Task { await library.save(snapshot) }
                }, compact: true, isActive: store.phase != .idle)
            }
        }

        private func window(_ host: NSView, width: Double, height: Double = 800) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            return window
        }

        private func layout(_ host: NSView) async {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(200))
            host.layoutSubtreeIfNeeded()
        }

        private func value(_ name: String, _ object: NSObject) -> Any? {
            guard object.responds(to: NSSelectorFromString(name)) else { return nil }
            return object.value(forKey: name)
        }

        private func elements(_ root: NSObject) -> [NSObject] {
            [root] + (value("accessibilityChildren", root) as? [NSObject] ?? []).flatMap(elements)
        }

        private func element(in root: NSObject, labelPrefix: String) -> NSObject? {
            elements(root).first { object in
                ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].contains {
                    (value($0, object) as? String)?.hasPrefix(labelPrefix) == true
                }
            }
        }

        private func button(in root: NSObject, title: String) -> NSObject? {
            elements(root).first { $0.responds(to: NSSelectorFromString("accessibilityPerformPress")) &&
                (value("accessibilityLabel", $0) as? String ?? value("accessibilityTitle", $0) as? String) == title }
        }

        private func frame(_ object: NSObject) -> CGRect {
            (value("accessibilityFrame", object) as? NSValue)?.rectValue ?? .zero
        }
    }
}
