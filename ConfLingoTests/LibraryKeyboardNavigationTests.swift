import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LibraryKeyboardNavigationTests {
    @Test(arguments: [16.0, 48.0], [640.0, 1180.0])
    func savedSessionActionsRemainVisibleAfterEvidenceJump(fontSize: Double, width: Double) async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let session = UUID()
        let events = (0..<40).map { insightEvent(session: session, text: "Synthetic transcript \($0)", offset: Double($0)) }
        let target = try #require(events.last)
        let card = MeetingInsight(kind: .answerSuggestion, text: "Evidence", priority: 0, evidenceIDs: [target.id])
        let snapshot = MeetingExportSnapshot(title: "Keyboard review", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
            sessionID: session, events: events, candidates: [], summary: nil)
        let saved = SavedSession(version: 1, createdAt: Date(), updatedAt: Date(), snapshot: .meeting(snapshot, [card]))
        var returned = false
        let host = NSHostingView(rootView: SavedSessionView(saved: saved, fontSize: fontSize, back: { returned = true }, delete: {}))
        let window = makeWindow(host, width: width)
        defer { window.close() }
        await layout(host)
        let evidence = try #require(elements(host).first { label($0).contains("の発話を見る") })
        _ = evidence.perform(NSSelectorFromString("accessibilityPerformPress"))
        await layout(host)
        let scroll = try #require(descendants(host, of: NSScrollView.self).first)
        #expect(scroll.documentVisibleRect.minY > 500, "Evidence navigation must move to the late utterance")
        for title in ["一覧へ", "Markdownを書き出す", "削除"] {
            let button = try #require(elements(host).first { label($0) == title }, "Missing action: \(title)")
            #expect(isVisible(button, in: host), "Action must remain in the viewport: \(title)")
        }
        let back = try #require(elements(host).first { label($0) == "一覧へ" })
        _ = back.perform(NSSelectorFromString("accessibilityPerformPress"))
        #expect(returned)
    }

    @Test(arguments: [16.0, 48.0], [640.0, 1180.0])
    func libraryBodySupportsKeyboardPaging(fontSize: Double, width: Double) async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(String(repeating: "本文の長い行を読み進めます。\n", count: 100)), title: "Keyboard document")
        let library = KnowledgeLibrary(files: files)
        let host = NSHostingView(rootView: VStack(spacing: 0) {
            KnowledgeLibraryView(library: library, fontSize: fontSize)
            // Text inputs stay in the key loop even when macOS skips buttons during Tab navigation.
            TextField("Keyboard test destination", text: .constant(""))
                .accessibilityLabel("Keyboard test destination")
        })
        let window = makeWindow(host, width: width)
        defer { window.close() }
        await layout(host)
        await library.open(saved.id)
        await layout(host)
        let body = try #require(elements(host).first { label($0) == "資料本文" }, "The body needs a keyboard focus destination")
        try focus(body)
        await layout(host)
        let scroll = try #require(descendants(host, of: NSScrollView.self).max {
            ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
        })
        let start = scroll.documentVisibleRect.minY
        try key(.pageDown, code: 121, window: window)
        await layout(host)
        #expect(scroll.documentVisibleRect.minY > start + 20)
        try key(.pageUp, code: 116, window: window)
        await layout(host)
        #expect(scroll.documentVisibleRect.minY < 4)
        try key(.end, code: 119, window: window)
        await layout(host)
        #expect(abs((scroll.documentView?.frame.height ?? 0) - scroll.documentVisibleRect.maxY) < 4)
        try key(.home, code: 115, window: window)
        await layout(host)
        #expect(scroll.documentVisibleRect.minY < 4)
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(window.firstResponder === textView)
        let destination = try #require(descendants(host, of: NSTextField.self).first { $0.isEditable },
            "The fixture must provide a Tab destination independently of button navigation settings")
        #expect(destination.canBecomeKeyView)
        print("Keyboard paging fixture: fullKeyboardAccess=\(NSApp.isFullKeyboardAccessEnabled)")
        try key(.tab, code: 48, window: window)
        await layout(host)
        #expect(window.firstResponder !== textView, "Tab must leave the read-only body")
        try focus(body)
        try key(.tab, code: 48, window: window, modifiers: .shift)
        await layout(host)
        #expect(window.firstResponder !== textView, "Shift+Tab must leave the read-only body")
    }

    @Test(arguments: [640.0, 1180.0])
    func settingsRevealsFocusedControlsInBothDirections(width: Double) async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let suite = "KeyboardSettings." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LLMSettings(defaults: defaults, keyStore: { _ in MemoryAPIKeyStore() })
        let host = NSHostingView(rootView: SettingsView(fontSize: .constant(48), alwaysOnTop: .constant(false),
            appearance: .constant("system"), answerLanguage: .constant(.japanese), llmSettings: settings,
            editDictionary: {}, prepare: {}))
        let window = makeWindow(host, width: width)
        defer { window.close() }
        await layout(host)
        for title in ["編集・APIキー設定", "辞書を管理", "接続を追加", "字幕の準備へ"] {
            let control = try #require(elements(host).first { label($0) == title })
            try focus(control)
            await layout(host)
            #expect(isVisible(control, in: host), "Focused control must be visible: \(title)")
        }
    }

    @Test(arguments: [16.0, 48.0], [false, true])
    func narrowRepositoryKeepsDocumentSelectionAndReadableBody(fontSize: Double, longNames: Bool) async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = UUID()
        let prefix = longNames ? String(repeating: "Sources/LongFeatureName/", count: 12) : ""
        let documents = ["README.md", "Review.swift"].map { filename in
            let path = prefix + filename
            let body = String(repeating: "\(path)の本文を読み進めます。\n", count: 40)
            let source = RepositorySource(snapshotID: snapshot, name: "Fixture", path: path, contentHash: KnowledgeArchive.hash(body))
            return KnowledgeArchive.Document(document: KnowledgeDocument(id: UUID(), title: filename, importedAt: Date(),
                characterCount: body.count, source: source), body: body)
        }
        let files = KnowledgeLibraryFiles(directory: root)
        let title = longNames ? String(repeating: "保存された仕様資料", count: 20) : "Repository"
        let saved = try await files.save(KnowledgeArchive(documents: documents), title: title)
        let library = KnowledgeLibrary(files: files)
        let host = NSHostingView(rootView: KnowledgeLibraryView(library: library, fontSize: fontSize))
        let window = makeWindow(host, width: 640)
        defer { window.close() }
        // Reserve the space consumed by the main window's navigation and typography toolbar.
        window.setContentSize(NSSize(width: 640, height: 400))
        await layout(host)
        await library.open(saved.id)
        await layout(host)
        if longNames {
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("keyboard-long-path-\(Int(fontSize)).png")
            try data.write(to: imageURL)
            print("Long-path layout screenshot: \(imageURL.path)")
        }
        for document in documents {
            let button = try #require(elements(host).first { label($0) == document.document.displayTitle })
            #expect(isVisible(button, in: host))
            _ = button.perform(NSSelectorFromString("accessibilityPerformPress"))
            await layout(host)
            let body = try #require(elements(host).first { label($0) == "資料本文" } as? NSTextView)
            let scroll = try #require(body.enclosingScrollView)
            #expect(scroll.visibleRect.height >= fontSize * 1.2, "At least a full line must remain readable")
            #expect(host.bounds.contains(host.convert(scroll.bounds, from: scroll)))
            #expect(body.string == document.body)
            #expect(!body.isEditable && body.isSelectable)
            try focus(body)
            try key(.pageDown, code: 121, window: window)
            await layout(host)
            #expect(scroll.documentVisibleRect.minY > 20)
        }
    }

    private func focus(_ element: NSObject) throws {
        if let cell = element as? NSCell, let control = cell.controlView {
            try #require(control.window?.makeFirstResponder(control) == true)
            return
        }
        try #require(element.responds(to: NSSelectorFromString("setAccessibilityFocused:")))
        element.setValue(true, forKey: "accessibilityFocused")
    }

    private func key(_ key: KeyEquivalent, code: UInt16, window: NSWindow, modifiers: NSEvent.ModifierFlags = []) throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: String(key.character),
            charactersIgnoringModifiers: String(key.character), isARepeat: false, keyCode: code))
        window.sendEvent(event)
    }

    private func makeWindow(_ host: NSView, width: Double) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 520),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func layout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }

    private func value(_ name: String, of element: NSObject) -> Any? {
        guard element.responds(to: NSSelectorFromString(name)) else { return nil }
        return element.value(forKey: name)
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        [root] + (value("accessibilityChildren", of: root) as? [NSObject] ?? []).flatMap { elements($0) }
    }

    private func label(_ element: NSObject) -> String {
        (value("accessibilityLabel", of: element) as? String) ?? (value("accessibilityTitle", of: element) as? String) ?? ""
    }

    private func isVisible(_ element: NSObject, in host: NSView) -> Bool {
        guard let frame = value("accessibilityFrame", of: element) as? NSValue, let window = host.window else { return false }
        let viewport = window.convertToScreen(host.convert(host.bounds, to: nil))
        guard !frame.rectValue.isEmpty, viewport.contains(frame.rectValue) else { return false }
        var ancestor = value("accessibilityParent", of: element) as? NSObject
        var visited: Set<ObjectIdentifier> = []
        while let parent = ancestor, visited.insert(ObjectIdentifier(parent)).inserted {
            if value("accessibilityRole", of: parent) as? String == "AXScrollArea",
               let clip = value("accessibilityFrame", of: parent) as? NSValue,
               !clip.rectValue.contains(frame.rectValue) { return false }
            ancestor = value("accessibilityParent", of: parent) as? NSObject
        }
        return true
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }
}
