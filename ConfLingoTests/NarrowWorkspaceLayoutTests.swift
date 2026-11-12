import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct NarrowWorkspaceLayoutTests {
    @Test(arguments: [16.0, 48.0], [false, true])
    func evidenceLinkRevealsTranscriptFromSupportPane(fontSize: Double, review: Bool) async throws {
        let suite = "ReviewEvidence." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = MeetingPreview.make(activity: AudioInputUse(), defaults: defaults)
        meeting.consentConfirmed = true
        await meeting.start()
        MeetingPreview.populate(meeting, count: 40)
        if review { await meeting.end() }
        defer { meeting.translations.reset(sessionID: UUID()) }
        let host = NSHostingView(rootView: AppShellView(destination: .meeting, phase: meeting.phase, navigate: { _ in }) {
            MeetingWorkspaceView(meeting: meeting, fontSize: .constant(fontSize), compact: {})
        })
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 640, height: 520)
        let transcript = try #require(leafScrolls(host).max { documentHeight($0) < documentHeight($1) })
        let outer = try #require(descendants(host, of: NSScrollView.self).first { scroll in
            guard let document = scroll.documentView else { return false }
            return descendants(document, of: NSScrollView.self).count >= 2
        })
        let outerBottom = max(0, documentHeight(outer) - outer.contentSize.height)
        outer.contentView.scroll(to: NSPoint(x: 0, y: outerBottom))
        outer.reflectScrolledClipView(outer.contentView)
        await resize(window, width: 640, height: 520)
        meeting.revealEvidence(try #require(meeting.store.finals.first).id)
        await resize(window, width: 640, height: 520)
        await resize(window, width: 640, height: 520)
        #expect(transcript.documentVisibleRect.minY < 25, "The requested first utterance must be visible")
        #expect(transcript.visibleRect.height >= 100, "Evidence navigation must reveal readable transcript text")
        outer.contentView.scroll(to: NSPoint(x: 0, y: outerBottom))
        outer.reflectScrolledClipView(outer.contentView)
        await resize(window, width: 640, height: 520)
        meeting.revealEvidence(try #require(meeting.store.finals.first).id)
        await resize(window, width: 640, height: 520)
        await resize(window, width: 640, height: 520)
        #expect(transcript.visibleRect.height >= 100, "Requesting the same evidence must reveal it again")
        #expect(transcript.documentVisibleRect.minY < 25)
        if !review { await meeting.end() }
    }

    @Test(arguments: [16.0, 32.0, 48.0], [false, true])
    func meetingKeepsReadableTranscriptAndLatestAfterResizing(fontSize: Double, review: Bool) async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        meeting.mode = .translation
        meeting.consentConfirmed = true
        await meeting.start()
        MeetingPreview.populate(meeting, count: 40)
        if review { await meeting.end() }
        defer { meeting.translations.reset(sessionID: UUID()) }
        let host = NSHostingView(rootView: AppShellView(destination: .meeting, phase: meeting.phase, navigate: { _ in }) {
            MeetingWorkspaceView(meeting: meeting, fontSize: .constant(fontSize), compact: {})
        })
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 1180, height: 780)
        let transcript = try #require(leafScrolls(host).max { documentHeight($0) < documentHeight($1) })
        let sessionID = meeting.store.sessionID
        for size in [NSSize(width: 742, height: 562), NSSize(width: 640, height: 520), NSSize(width: 1180, height: 780)] {
            await resize(window, width: size.width, height: size.height)
            #expect(leafScrolls(host).contains { $0 === transcript }, "Resizing must preserve the transcript scroll view")
            #expect(transcript.contentSize.height >= max(160, fontSize * 4), "The transcript needs room for several lines at \(size)")
            #expect(documentHeight(transcript) - transcript.documentVisibleRect.maxY < 25, "Following latest must remain at the final text")
            #expect(meeting.store.sessionID == sessionID)
            #expect(meeting.store.finals.count == 40)
        }
        if !review { await meeting.end() }
    }

    @Test(arguments: [16.0, 32.0, 48.0], [false, true])
    func conferenceKeepsBothPanesReadable(fontSize: Double, translation: Bool) async throws {
        let store = SessionStore()
        for index in 0..<40 {
            let id = try #require(store.appendFinal("Sentence \(index). Read the source and its translation without losing the conversation."))
            let unit = try #require(store.bufferSegment(id))
            store.applyTranslation(id: unit.id, japanese: "字幕\(index)。原文と訳文の両方を読みながら会話を確認します。")
        }
        let host = NSHostingView(rootView: AppShellView(destination: .live, phase: .idle, navigate: { _ in }) {
            ConferenceLiveView(store: store, sourceLanguage: "en-US", targetLanguage: translation ? "ja" : nil,
                               profileName: "Test", fontSize: .constant(fontSize), editSettings: {}, clear: {})
        })
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 1180, height: 780)
        let panes = leafScrolls(host).filter { documentHeight($0) > 1_000 }
        try #require(panes.count == (translation ? 2 : 1))
        for size in [NSSize(width: 742, height: 562), NSSize(width: 640, height: 520), NSSize(width: 1180, height: 780)] {
            await resize(window, width: size.width, height: size.height)
            for pane in panes {
                #expect(leafScrolls(host).contains { $0 === pane })
                #expect(pane.contentSize.height >= max(160, fontSize * 4), "Each subtitle pane needs readable height at \(size)")
                #expect(pane.frame.height < size.height, "A pane must stay bounded so long history scrolls inside it")
                #expect(documentHeight(pane) > pane.contentSize.height, "Long subtitles must remain independently scrollable")
                #expect(documentHeight(pane) - pane.documentVisibleRect.maxY < 25, "Resizing while following latest must keep the final subtitle visible")
            }
        }
    }

    @Test(arguments: [false, true])
    func mainMeetingWindowKeepsTranscriptReadableBelowToolbar(review: Bool) async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        meeting.mode = .translation
        meeting.consentConfirmed = true
        await meeting.start()
        MeetingPreview.populate(meeting, count: 40)
        if review { await meeting.end() }
        defer { meeting.translations.reset(sessionID: UUID()) }
        let host = NSHostingView(rootView: ContentView(preview: true, meeting: meeting, meetingPreview: true))
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 1180, height: 780)
        let transcript = try #require(leafScrolls(host).max { documentHeight($0) < documentHeight($1) })
        for size in [NSSize(width: 742, height: 562), NSSize(width: 640, height: 520), NSSize(width: 1180, height: 780)] {
            await resize(window, width: size.width, height: size.height)
            #expect(leafScrolls(host).contains { $0 === transcript })
            #expect(transcript.contentSize.height >= 160)
            #expect(transcript.frame.height < size.height)
            #expect(documentHeight(transcript) - transcript.documentVisibleRect.maxY < 25)
        }
        if !review { await meeting.end() }
    }

    @Test func compactNavigationDoesNotConsumeMultipleRows() async {
        let content = NSView()
        let host = NSHostingView(rootView: AppShellView(destination: .home, phase: .idle, navigate: { _ in }) {
            NativeContent(view: content)
        })
        let window = makeWindow(host)
        defer { window.close() }
        for width in [742.0, 640.0] {
            await resize(window, width: width, height: 520)
            #expect(host.frame.height - content.frame.height <= 65, "Navigation must leave the remaining height for content")
        }
    }

    private struct NativeContent: NSViewRepresentable {
        let view: NSView
        func makeNSView(context: Context) -> NSView { view }
        func updateNSView(_ nsView: NSView, context: Context) {}
    }

    private func makeWindow(_ view: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    private func resize(_ window: NSWindow, width: CGFloat, height: CGFloat) async {
        window.setContentSize(NSSize(width: width, height: height))
        window.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(120))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func documentHeight(_ scroll: NSScrollView) -> CGFloat { scroll.documentView?.frame.height ?? 0 }

    private func leafScrolls(_ view: NSView) -> [NSScrollView] {
        descendants(view, of: NSScrollView.self).filter { scroll in
            guard let document = scroll.documentView else { return false }
            return descendants(document, of: NSScrollView.self).isEmpty
        }
    }

    private func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, of: type) }
    }
}
