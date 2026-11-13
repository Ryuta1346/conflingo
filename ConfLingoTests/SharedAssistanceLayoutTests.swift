import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct SharedAssistanceLayoutTests {
    @Test(arguments: [false, true])
    func researchSheetRendersWithoutClippingAtNarrowWidth(dark: Bool) async throws {
        let fixture = ResearchFixture()
        fixture.research.setPermission(true)
        await fixture.research.run(question: "question", language: .english)
        let view = WebResearchView(research: fixture.research, language: .english, enabled: true)
            .preferredColorScheme(dark ? .dark : .light)
        try await render(view, size: NSSize(width: 520, height: 720), filename: "research-\(dark ? "dark" : "light")")
    }

    @Test func conferenceShowsSubtitlesBesideAssistance() async throws {
        try await render(ContentView(preview: true), size: NSSize(width: 1440, height: 900), filename: "conference-wide")
    }

    private func render<V: View>(_ view: V, size: NSSize, filename: String) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        #expect(host.frame.width <= size.width + 1)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("conflingo-\(filename).png"))
    }
}
