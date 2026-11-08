import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MeetingLayoutTests {
    @Test func resizingAndFloatingKeepTranscriptIdentityAndReadingPosition() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        meeting.consentConfirmed = true
        await meeting.start()
        MeetingPreview.populate(meeting, count: 80)
        let host = NSHostingView(rootView: AppShellView(destination: .meeting, phase: .listening, navigate: { _ in }) {
            MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {})
        })
        let window = makeWindow(host)
        let suite = "MeetingLayoutTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let floating = MeetingFloatingPanel(defaults: defaults)
        defer {
            floating.hide()
            floating.panel?.close()
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
        await resize(window, width: 1280, height: 800)
        let scrolls = descendants(host, of: NSScrollView.self)
        try #require(scrolls.count == 2)
        let transcript = try #require(scrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        let evidence = try #require(meeting.store.finals.first)
        meeting.revealEvidence(evidence.id)
        await layout(window)
        #expect(transcript.documentVisibleRect.minY < 1000)
        await resize(window, width: 720, height: 560)
        #expect(Set(descendants(host, of: NSScrollView.self).map(ObjectIdentifier.init)) == Set(scrolls.map(ObjectIdentifier.init)))
        #expect(transcript.documentVisibleRect.minY < 1000)
        floating.mainWindow = window
        floating.show(meeting: meeting, compactMain: true)
        floating.hide()
        await resize(window, width: 1280, height: 800)
        let newest = TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .systemAudio,
                                     languageCode: "en-US", startOffset: 1000, endOffset: 1001,
                                     text: "A new final after resizing.", isFinal: true, revision: 1, sourceStartTime: 1000)
        meeting.store.receive(newest)
        await layout(window)
        #expect(transcript.documentVisibleRect.minY < 1000)
        #expect(meeting.phase == .listening)
        await meeting.end()
        await layout(window)
        #expect(meeting.page == .review)
        #expect(Set(descendants(host, of: NSScrollView.self).map(ObjectIdentifier.init)) == Set(scrolls.map(ObjectIdentifier.init)))
    }

    @Test func panelHideCloseAndRestoreNeverStopOrReplaceMeeting() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        meeting.consentConfirmed = true
        await meeting.start()
        let id = meeting.store.sessionID
        let suite = "MeetingPanelTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let floating = MeetingFloatingPanel(defaults: defaults)
        defer { floating.hide(); floating.panel?.close(); defaults.removePersistentDomain(forName: suite) }
        let key = NSApp.keyWindow
        floating.show(meeting: meeting)
        let first = try #require(floating.panel)
        #expect(first.isVisible)
        #expect(NSApp.keyWindow === key)
        #expect(first.styleMask.contains(.nonactivatingPanel))
        first.setFrame(NSRect(x: 150, y: 150, width: 460, height: 500), display: false)
        floating.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: first))
        #expect(defaults.string(forKey: "meetingPanelFrame") != nil)
        #expect(!floating.windowShouldClose(first))
        #expect(!first.isVisible)
        #expect(meeting.phase == .listening)
        floating.show(meeting: meeting)
        #expect(floating.panel === first)
        #expect(meeting.store.sessionID == id)
        #expect(meeting.phase == .listening)
        await meeting.end()
        #expect(meeting.page == .review)
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    private func resize(_ window: NSWindow, width: CGFloat, height: CGFloat) async {
        window.setContentSize(NSSize(width: width, height: height))
        await layout(window)
    }

    private func layout(_ window: NSWindow) async {
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }
}
