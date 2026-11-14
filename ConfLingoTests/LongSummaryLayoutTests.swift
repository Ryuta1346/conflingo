import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LongSummaryLayoutTests {
    @Test(arguments: [440.0, 620.0])
    func hundredSectionConfirmationFitsAndCanCancel(width: Double) async throws {
        let releaseAccessibility = TestAccessibility.shared.enable()
        defer { releaseAccessibility() }
        let meeting = makeMeeting(count: 3_000, client: FakeInsightClient())
        await meeting.end()
        let plan = try meeting.summaryPlan()
        var dismissed = false
        let host = NSHostingView(rootView: SummaryConfirmationView(meeting: meeting, initialPlan: plan) { dismissed = true }
            .background(DesignTokens.canvas).preferredColorScheme(.light))
        let window = makeWindow(host, width: width)
        defer { window.close() }
        await layout(host)
        #expect(host.frame.width <= width + 1)
        let text = screenText(host)
        #expect(text.contains("3,000件"))
        #expect(text.contains("100区間／最大100要求"))
        #expect(text.contains("処理に時間がかかります"))
        #expect(text.contains("この内容を送って要約する"))
        try snapshot(host, name: "confirmation-\(Int(width))")
        try press("キャンセル", in: host)
        #expect(dismissed)
        #expect(!meeting.isSummaryPlanCurrent(plan))
    }

    @Test func narrowReviewShowsLimitAndCanStopLongSummary() async throws {
        let releaseAccessibility = TestAccessibility.shared.enable()
        defer { releaseAccessibility() }
        let client = FakeInsightClient()
        let gate = TestGate()
        client.gate = gate
        let meeting = makeMeeting(count: 601, client: client)
        await meeting.end()
        let plan = try meeting.summaryPlan()
        let operation = Task { await meeting.generateSummary(plan, consent: true) }
        await gate.entered.next()
        defer { gate.release(); operation.cancel() }
        let host = NSHostingView(rootView: ScrollView { MeetingReviewControls(meeting: meeting, fontSize: 16) }
            .background(DesignTokens.canvas).preferredColorScheme(.light))
        let window = makeWindow(host, width: 440)
        defer { window.close() }
        await layout(host)
        #expect(host.frame.width <= 441)
        let text = screenText(host)
        #expect(text.contains("最大100区間"))
        #expect(text.contains("0 / 21区間完了"))
        try snapshot(host, name: "review-440")
        try press("要約の送信を停止", in: host)
        gate.release()
        await operation.value
        #expect(meeting.summary.state == .interrupted)
        #expect(client.requests.count == 1)
    }

    private func makeMeeting(count: Int, client: FakeInsightClient) -> MeetingWorkspace {
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client)
        for index in 0..<count {
            meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "Synthetic speech \(index)", offset: Double(index)))
        }
        return meeting
    }

    private func makeWindow(_ host: NSView, width: Double) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    private func layout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }

    private func snapshot(_ host: NSView, name: String) throws {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("r5-summary-\(name).png"))
    }

    private func value(_ name: String, of element: NSObject) -> Any? {
        let selector = NSSelectorFromString(name)
        guard element.responds(to: selector) else { return nil }
        return element.perform(selector)?.takeUnretainedValue()
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        let children = value("accessibilityChildren", of: root) as? [NSObject] ?? []
        return [root] + children.flatMap { elements($0) }
    }

    private func screenText(_ root: NSObject) -> String {
        elements(root).flatMap { element in
            ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { value($0, of: element) as? String }
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
