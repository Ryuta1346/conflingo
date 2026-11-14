import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MeetingTermLayoutTests {
    @Test(arguments: [420.0, 780.0])
    func termsAndRetriedTranslationRemainReadable(width: Double) async throws {
        let suite = "MeetingTermLayout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = TermTranslationClient(outputs: [.failure])
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), defaults: defaults,
            translationClientFactory: { _, _ in client }, prepareTranslationModels: false)
        meeting.mode = .translation
        meeting.microphoneLocaleID = "en-US"
        meeting.documentTerms.addManual(term: "Photon", target: "未確認の訳語")
        try meeting.documentTerms.apply(sourceLanguage: "en", targetLanguage: nil, manual: [])
        let event = translationEvent(meeting.store.sessionID, text: "Photon")
        meeting.store.receive(event)
        await settleTranslations(meeting.translations)
        let host = NSHostingView(rootView: ScrollView { VStack(alignment: .leading, spacing: 16) {
            MeetingKnowledgeControls(meeting: meeting)
            Text(event.text).font(.title2)
            MeetingTranslationText(translations: meeting.translations, eventID: event.id, fontSize: 24)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading) }.background(DesignTokens.canvas).transaction { $0.disablesAnimations = true; $0.animation = nil })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1100),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        let releaseAccessibility = TestAccessibility.shared.enable()
        defer {
            window.close()
            releaseAccessibility()
            meeting.translations.reset(sessionID: UUID())
        }
        await layout(host)
        try press("資料から専門用語を適用（1語）", in: host)
        await layout(host)
        #expect(text(host).contains("固定訳語の指定はできません"))
        #expect(!text(host).contains("未確認の訳語"))
        #expect(text(host).contains("翻訳を再試行"))
        try await capture(host, name: "meeting-terms-\(Int(width))-failed")
        try press("翻訳を再試行", in: host)
        await settleTranslations(meeting.translations)
        await layout(host)
        #expect(host.frame.width <= width + 1)
        #expect(text(host).contains("translated Photon"))
        #expect(!text(host).contains("⟦"))
        try await capture(host, name: "meeting-terms-\(Int(width))-done")
    }

    private func layout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
    }

    private func capture(_ host: NSView, name: String) async throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/" + name + ".png"))
    }

    private func value(_ key: String, of object: NSObject) -> Any? {
        let selector = NSSelectorFromString(key)
        return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        [root] + (value("accessibilityChildren", of: root) as? [NSObject] ?? []).flatMap { elements($0) }
    }

    private func text(_ root: NSObject) -> String {
        elements(root).flatMap { element in
            ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { value($0, of: element) as? String }
        }.joined(separator: "\n")
    }

    private func press(_ title: String, in root: NSObject) throws {
        let action = NSSelectorFromString("accessibilityPerformPress")
        let button = try #require(elements(root).first {
            $0.responds(to: action) && (value("accessibilityLabel", of: $0) as? String == title
                || value("accessibilityTitle", of: $0) as? String == title)
        })
        _ = button.perform(action)
    }
}
