import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct MeetingLayoutTests {
    @Test func lateTranslationsKeepLatestVisibleAtLargeFontInNarrowWindow() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), translationClient: FakeMeetingTranslator())
        meeting.mode = .translation
        for index in 0..<8 {
            meeting.store.receive(TranscriptEvent(id: UUID(), sessionID: meeting.store.sessionID, origin: .systemAudio,
                languageCode: "en-US", startOffset: Double(index), endOffset: Double(index + 1),
                text: "Sentence \(index). " + String(repeating: "A long meeting transcript. ", count: 5),
                isFinal: true, revision: 1, sourceStartTime: Double(index)))
        }
        let host = NSHostingView(rootView: MeetingTranscriptView(meeting: meeting, fontSize: 32))
        let window = makeWindow(host)
        defer { window.close() }
        await resize(window, width: 420, height: 520)
        let scroll = try #require(descendants(host, of: NSScrollView.self).first)
        for lane in meeting.translations.lanes { meeting.translations.prepared(lane.id, generation: lane.generation) }
        for _ in 0..<10_000 {
            if !meeting.translations.isWorking { break }
            await Task.yield()
        }
        await layout(window)
        await layout(window)
        let height = try #require(scroll.documentView?.frame.height)
        #expect(height - scroll.documentVisibleRect.maxY < 25, "Late translations must remain visible when following latest")
        #expect(meeting.translations.completed.count == 8)
    }

    @Test func expansionPreservesMeetingDuringCaptureAndFailedStop() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(owner: .meeting))
        meeting.consentConfirmed = true
        await meeting.start()
        await meeting.pause()
        let navigation = ConferenceNavigation(destination: .settings)
        let suite = "MeetingExpansionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let floating = MeetingFloatingPanel(defaults: defaults)
        defer { floating.hide(); defaults.removePersistentDomain(forName: suite) }
        floating.expand = { navigation.requestMeetingExpansion(conferencePhase: .idle) }
        floating.show(meeting: meeting)
        await meeting.start()
        let id = meeting.store.sessionID
        floating.showMain()
        #expect(navigation.destination == .meeting)
        #expect(!navigation.showsStopConfirmation)
        #expect(meeting.phase == .listening)
        #expect(meeting.store.sessionID == id)
        #expect(floating.panel?.isVisible == false)
        await meeting.pause()
        navigation.request(.settings, phase: meeting.phase)
        floating.show(meeting: meeting)
        await meeting.start()
        fixture.system.stopError = .stop
        await meeting.end()
        #expect(meeting.phase == .stopping)
        floating.showMain()
        #expect(navigation.destination == .meeting)
        #expect(meeting.phase == .stopping)
        #expect(meeting.page == .live)
        #expect(meeting.store.sessionID == id)
        #expect(floating.panel?.isVisible == false)
        fixture.system.stopError = nil
        await meeting.retryStop()
        #expect(meeting.page == .review)
    }

    @Test func expansionKeepsPanelVisibleUntilNavigationSucceeds() throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        let navigation = ConferenceNavigation(destination: .settings)
        let suite = "MeetingExpansionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let floating = MeetingFloatingPanel(defaults: defaults)
        defer { floating.hide(); defaults.removePersistentDomain(forName: suite) }
        var conferencePhase = SessionPhase.listening
        floating.expand = { navigation.requestMeetingExpansion(conferencePhase: conferencePhase) }
        floating.show(meeting: meeting)
        floating.showMain()
        #expect(floating.panel?.isVisible == true)
        #expect(navigation.showsStopConfirmation)
        navigation.cancelNavigation()
        conferencePhase = .stopping
        floating.showMain()
        #expect(floating.panel?.isVisible == true)
        conferencePhase = .idle
        floating.showMain()
        #expect(navigation.destination == .meeting)
        #expect(floating.panel?.isVisible == false)
    }

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
        let scrolls = paneScrolls(host)
        try #require(scrolls.count == 2)
        let transcript = try #require(scrolls.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) })
        let evidence = try #require(meeting.store.finals.first)
        meeting.revealEvidence(evidence.id)
        await layout(window)
        #expect(transcript.documentVisibleRect.minY < 1000)
        await resize(window, width: 720, height: 560)
        #expect(Set(scrolls.map(ObjectIdentifier.init)).isSubset(of: Set(paneScrolls(host).map(ObjectIdentifier.init))))
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
        #expect(Set(scrolls.map(ObjectIdentifier.init)).isSubset(of: Set(paneScrolls(host).map(ObjectIdentifier.init))))
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
