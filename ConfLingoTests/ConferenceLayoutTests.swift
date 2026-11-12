import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized)
struct ConferenceLayoutTests {
    @Test(arguments: [false, true])
    func resizingTranscriptKeepsScrollViewsAndReadingPosition(inShell: Bool) async throws {
        let store = SessionStore()
        for index in 0..<80 {
            let id = try #require(store.appendFinal("Sentence \(index). This is a long transcript for reading history."))
            let unit = try #require(store.bufferSegment(id))
            store.applyTranslation(id: unit.id, japanese: "字幕 \(index)。履歴を読み返すための長い会話です。")
        }
        let live = ConferenceLiveView(
            store: store, sourceLanguage: "en-US", targetLanguage: "ja", profileName: "Test",
            fontSize: .constant(16), editSettings: {}, clear: {}
        )
        let host = NSHostingView(rootView: Group {
            if inShell {
                AppShellView(destination: .live, phase: .idle, navigate: { _ in }) { live }
            } else {
                live
            }
        })
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 1100)
        let scrollViews = paneScrolls(host)
        try #require(scrollViews.count == 2)
        for scroll in scrollViews {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
            scroll.reflectScrolledClipView(scroll.contentView)
            try await scrollUp(scroll)
        }
        await resize(window, width: 700)
        let narrowViews = paneScrolls(host)
        #expect(Set(scrollViews.map(ObjectIdentifier.init)).isSubset(of: Set(narrowViews.map(ObjectIdentifier.init))))
        for scroll in scrollViews {
            #expect(scroll.documentVisibleRect.minY < 1000)
        }
        await resize(window, width: 1100)
        #expect(Set(paneScrolls(host).map(ObjectIdentifier.init)) == Set(scrollViews.map(ObjectIdentifier.init)))
        let id = try #require(store.appendFinal("A new sentence after resizing."))
        let unit = try #require(store.bufferSegment(id))
        store.applyTranslation(id: unit.id, japanese: "サイズ変更後の新しい字幕です。")
        await resize(window, width: 1100)
        for scroll in scrollViews {
            #expect(scroll.documentVisibleRect.minY < 1000, "New subtitles must not resume following while reading history")
        }
    }

    private func scrollUp(_ scroll: NSScrollView) async throws {
        for phase in [CGScrollPhase.began, .changed, .ended] {
            let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                            wheel1: phase == .ended ? 0 : 10, wheel2: 0, wheel3: 0))
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
            scroll.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
            try await Task.sleep(for: .milliseconds(30))
        }
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    private func resize(_ window: NSWindow, width: CGFloat) async {
        window.setContentSize(NSSize(width: width, height: 780))
        window.contentView?.layoutSubtreeIfNeeded()
        // Give SwiftUI's deferred layout/observation updates a run-loop turn.
        try? await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func paneScrolls(_ view: NSView) -> [NSScrollView] {
        descendants(view, of: NSScrollView.self).filter { scroll in
            guard let document = scroll.documentView else { return false }
            return descendants(document, of: NSScrollView.self).isEmpty
        }
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }
}
