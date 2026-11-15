import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

extension AppKitIntegrationTests {
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DesignSystemTests {
        @Test func saveFailureKeepsReadableSummaryAndRecoveryClearsDetails() async throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("DR3-" + UUID().uuidString)
            try Data("not a directory".utf8).write(to: root)
            defer { try? FileManager.default.removeItem(at: root) }
            let library = SessionsLibrary(files: SessionFiles(directory: root))
            let snapshot = sessionFixture(title: "保持する会議")
            await library.save(snapshot)
            let failure = try #require(library.failure)
            #expect(failure.kind == .failure)
            #expect(failure.text.contains("現在の内容は保持"))
            #expect(failure.details != nil)
            #expect(!failure.text.contains(try #require(failure.details)))
            #expect(library.savedSnapshots.isEmpty)
            try FileManager.default.removeItem(at: root)
            await library.save(snapshot)
            #expect(library.failure == nil)
            #expect(library.matches(snapshot))
        }

        @Test func importResultDistinguishesFailureSuccessAndReset() async {
            let knowledge = KnowledgeStore()
            await knowledge.add(data: Data(), filename: "empty.txt")
            #expect(knowledge.notice?.kind == .failure)
            await knowledge.add(data: Data("A useful document for the meeting".utf8), filename: "notes.txt")
            #expect(knowledge.notice?.kind == .success)
            #expect(knowledge.notice?.details == nil)
            knowledge.reset()
            #expect(knowledge.notice == nil)
        }

        @Test func keyFailureAndRecoveryDoNotExposeSecrets() {
            let store = DR3KeyStore()
            let credentials = APIKeyCredentials(store: store)
            store.fails = true
            #expect(!credentials.save("secret-key"))
            #expect(credentials.notice?.kind == .failure)
            #expect(credentials.notice?.details == nil)
            store.fails = false
            #expect(credentials.save("secret-key"))
            #expect(credentials.notice?.kind == .success)
            #expect(!credentials.message.contains("secret-key"))
            credentials.delete()
            #expect(credentials.notice?.kind == .success)
        }

        @Test func failureDetailsStartCollapsedAndCanBeReadWithoutChangingSummary() async throws {
            let fixture = DR3Host(InlineMessage(.failure, "保存できません。内容は保持しています。", details: "The file could not be opened."))
            defer { fixture.close() }
            await fixture.layout()
            #expect(fixture.strings.contains { $0.contains("内容は保持") })
            #expect(!fixture.strings.contains { $0.contains("The file") })
            let disclosure = try #require(fixture.element("詳細"))
            _ = disclosure.perform(NSSelectorFromString("accessibilityPerformPress"))
            await fixture.layout()
            #expect(fixture.strings.contains { $0.contains("The file could not be opened.") })
            #expect(fixture.strings.contains { $0.contains("内容は保持") })
        }

        @Test(arguments: AppButtonStyle.Kind.allCases)
        func buttonStylesKeepActionsAndDisabledState(kind: AppButtonStyle.Kind) async throws {
            var count = 0
            let fixture = DR3Host(VStack {
                Button("実行") { count += 1 }.buttonStyle(AppButtonStyle(kind))
                Button("無効") { count += 100 }.buttonStyle(AppButtonStyle(kind)).disabled(true)
            })
            defer { fixture.close() }
            await fixture.layout()
            let enabled = try #require(fixture.element("実行"))
            let disabled = try #require(fixture.element("無効"))
            #expect(fixture.value("isAccessibilityEnabled", disabled) as? Bool == false)
            _ = enabled.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(count == 1)
            _ = disabled.perform(NSSelectorFromString("accessibilityPerformPress"))
            #expect(count == 1)
        }

        @Test(arguments: AppButtonStyle.Kind.allCases)
        func buttonStylesSupportKeyboardFocusAndSpace(kind: AppButtonStyle.Kind) async throws {
            try #require(NSApp.isFullKeyboardAccessEnabled)
            var count = 0
            let fixture = DR3Host(Button("キーボードで実行") { count += 1 }.buttonStyle(AppButtonStyle(kind)))
            defer { fixture.close() }
            await fixture.layout()
            let button = try #require(fixture.element("キーボードで実行"))
            fixture.window.makeFirstResponder(nil)
            for _ in 0..<3 {
                fixture.window.selectNextKeyView(nil)
                await fixture.layout()
                if fixture.value("isAccessibilityFocused", button) as? Bool == true { break }
            }
            #expect(fixture.value("isAccessibilityFocused", button) as? Bool == true)
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = try #require(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: fixture.window.windowNumber, context: nil,
                    characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
                fixture.window.sendEvent(event)
            }
            await fixture.layout()
            #expect(count == 1)
        }

        @Test(arguments: [NSAppearance.Name.aqua, .darkAqua])
        func primaryButtonTextHasReadableContrast(appearance: NSAppearance.Name) throws {
            let appearance = try #require(NSAppearance(named: appearance))
            var foreground: NSColor = .clear
            var background: NSColor = .clear
            appearance.performAsCurrentDrawingAppearance {
                foreground = NSColor(DesignTokens.onAccent).usingColorSpace(.sRGB) ?? .clear
                background = NSColor(DesignTokens.accent).usingColorSpace(.sRGB) ?? .clear
            }
            let first = luminance(foreground), second = luminance(background)
            #expect((max(first, second) + 0.05) / (min(first, second) + 0.05) >= 4.5)
        }

        private func luminance(_ color: NSColor) -> Double {
            let values = [color.redComponent, color.greenComponent, color.blueComponent].map {
                $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4)
            }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
    }
}

@MainActor
private final class DR3KeyStore: APIKeyStore {
    var fails = false
    func read() async throws -> String? { nil }
    func save(_ key: String) throws { if fails { throw InsightFailure.keyStorage } }
    func delete() throws { if fails { throw InsightFailure.keyStorage } }
}

@MainActor
final class DR3Host {
    let host: NSView
    let window: NSWindow
    private let release: () -> Void
    init<V: View>(_ view: V, width: Double = 640, height: Double = 520, padding: CGFloat = 24, nonactivating: Bool = false) {
        release = TestAccessibility.shared.enable()
        host = NSHostingView(rootView: view.padding(padding))
        let windowType: NSWindow.Type = nonactivating ? NSPanel.self : NSWindow.self
        var style: NSWindow.StyleMask = [.titled, .resizable]
        if nonactivating { style.insert(.nonactivatingPanel) }
        window = windowType.init(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                 styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
    }
    func close() { window.close(); release() }
    func layout() async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }
    func value(_ key: String, _ object: NSObject) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func elements(_ root: NSObject) -> [NSObject] {
        [root] + (value("accessibilityChildren", root) as? [NSObject] ?? []).flatMap { elements($0) }
    }
    var strings: [String] {
        elements(host).flatMap { object in
            ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { value($0, object) as? String }
        }
    }
    func element(_ label: String) -> NSObject? {
        elements(host).first {
            $0.responds(to: NSSelectorFromString("accessibilityPerformPress")) &&
            (value("accessibilityLabel", $0) as? String == label || value("accessibilityTitle", $0) as? String == label)
        }
    }
}
