import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LiveTranscriptLayoutTests {
    @Test func conferenceCacheHitsStillObserveFinalsTranslationsAndClear() async throws {
        let store = SessionStore()
        let first = try #require(store.appendFinal("First source."))
        let unit = try #require(store.bufferSegment(first))
        let host = NSHostingView(rootView: ConferenceLiveView(store: store, sourceLanguage: "en", targetLanguage: "ja",
            profileName: "Synthetic", fontSize: .constant(16), editSettings: {}, clear: {}))
        let window = makeWindow(host, width: 1100)
        let previous = enableAccessibility()
        defer { window.close(); restoreAccessibility(previous) }
        await layout(host)
        store.updateVolatile("Partial one")
        await layout(host)
        store.updateVolatile("Partial two")
        await layout(host)
        #expect(text(host).contains("Partial two"))
        store.applyTranslation(id: unit.id, japanese: "最初の訳文")
        await layout(host)
        #expect(text(host).contains("最初の訳文"))
        let next = try #require(store.appendFinal("Second source."))
        _ = try #require(store.bufferSegment(next))
        await layout(host)
        #expect(text(host).contains("Second source."))
        store.reset()
        await layout(host)
        #expect(text(host).contains("字幕を待っています"))
        #expect(!text(host).contains("Second source."))
    }

    @Test func meetingEvidenceRemainsVisibleDuringUpdatesThenReturnsToLatest() async throws {
        let suite = "r5-2-layout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: FakeInsightClient(),
            defaults: defaults, translationClientFactory: { _, _ in FakeMeetingTranslator() }, prepareTranslationModels: false)
        for index in 0..<100 {
            meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "History row \(index)", offset: Double(index)))
        }
        meeting.mode = .translation
        let host = NSHostingView(rootView: MeetingTranscriptView(meeting: meeting, fontSize: 16))
        let window = makeWindow(host, width: 620)
        let previous = enableAccessibility()
        defer { window.close(); restoreAccessibility(previous) }
        await layout(host)
        meeting.revealEvidence(meeting.store.finals[3].id)
        await layout(host)
        let scroll = try transcriptScroll(in: host)
        #expect(try viewport(of: scroll).intersects(frame(of: "History row 3", in: host)))
        #expect(text(host).contains("履歴を表示中"))
        meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "New partial", offset: 101, final: false))
        meeting.translations.receive(try #require(meeting.store.finals.last), targetLanguage: "ja")
        await layout(host)
        #expect(try viewport(of: scroll).intersects(frame(of: "History row 3", in: host)))
        #expect(text(host).contains("履歴を表示中"))
        #expect(meeting.translations.completed.count == 1)
        try press("最新へ", in: host)
        await layout(host)
        #expect(text(host).contains("New partial"))
        #expect(!text(host).contains("履歴を表示中"))
        window.setContentSize(NSSize(width: 540, height: 650))
        await layout(host)
        let document = try #require(scroll.documentView)
        #expect(scroll.contentView.bounds.maxY >= document.bounds.maxY - 24)
    }

    @Test func conferenceManualHistoryScrollIsNotTakenOverByPartialUpdates() async throws {
        let store = SessionStore()
        for index in 0..<100 { store.appendFinal("Conference history \(index).") }
        let host = NSHostingView(rootView: ConferenceLiveView(store: store, sourceLanguage: "en", targetLanguage: nil,
            profileName: "Synthetic", fontSize: .constant(16), editSettings: {}, clear: {}))
        let window = makeWindow(host, width: 620)
        let previous = enableAccessibility()
        defer { window.close(); restoreAccessibility(previous) }
        await layout(host)
        let scroll = try transcriptScroll(in: host)
        for phase in [CGScrollPhase.began, .changed, .ended] {
            let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                wheel1: phase == .ended ? 0 : 400, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
            await layout(host)
        }
        await layout(host)
        #expect(text(host).contains("履歴を表示中"))
        let visible = try viewport(of: scroll).insetBy(dx: 0, dy: 100)
        let historyTitles = elements(host).compactMap { value("accessibilityValue", of: $0) as? String }
            .filter { $0.hasPrefix("Conference history ") }
        let anchor = try #require(try historyTitles.first { title in
            try visible.contains(frame(of: title, in: host))
        })
        store.updateVolatile("New conference partial")
        await layout(host)
        #expect(try viewport(of: scroll).intersects(frame(of: anchor, in: host)))
        #expect(text(host).contains("履歴を表示中"))
        try press("最新へ", in: host)
        await layout(host)
        #expect(text(host).contains("New conference partial"))
    }

    private func enableAccessibility() -> Any? {
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(attribute)
        NSApp.accessibilitySetValue(true, forAttribute: attribute)
        return previous
    }

    private func restoreAccessibility(_ previous: Any?) {
        NSApp.accessibilitySetValue(previous ?? false, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
    }

    private func makeWindow(_ host: NSView, width: Double) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
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

    private func transcriptScroll(in root: NSView) throws -> NSScrollView {
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        return try #require(descendants(root).compactMap { $0 as? NSScrollView }.max {
            ($0.documentView?.bounds.height ?? 0) < ($1.documentView?.bounds.height ?? 0)
        })
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

    private func frame(of title: String, in root: NSObject) throws -> CGRect {
        let element = try #require(elements(root).first {
            value("accessibilityValue", of: $0) as? String == title
                || value("accessibilityLabel", of: $0) as? String == title
        })
        let selector = NSSelectorFromString("accessibilityFrame")
        try #require(element.responds(to: selector))
        // SwiftUI's AX element exposes the selector without publicly conforming to NSAccessibility.
        typealias FrameGetter = @convention(c) (AnyObject, Selector) -> CGRect
        let getter = unsafeBitCast(element.method(for: selector), to: FrameGetter.self)
        return getter(element, selector)
    }

    private func viewport(of scroll: NSScrollView) throws -> CGRect {
        let window = try #require(scroll.window)
        return window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
    }
}
