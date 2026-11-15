import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

// DR1（D03・D05・D14）の回帰テスト。docs/design/dr1-small-fixes-plan.md を参照。

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingEndConfirmationTests {
    @Test(arguments: [false, true])
    func endingAsksFirstAndCancellingKeepsTheMeeting(paused: Bool) async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        try await fixture.microphone.emit("Keep after cancelling", time: 1)
        if paused { await meeting.pause() }
        let phase = meeting.phase

        meeting.requestEnd()
        #expect(meeting.showsEndConfirmation)
        #expect(meeting.page == .live, "Asking must not end the meeting")
        #expect(meeting.phase == phase)

        meeting.showsEndConfirmation = false
        #expect(meeting.confirmEnd() == nil, "A cancelled confirmation must not end the meeting later")
        #expect(meeting.page == .live)
        #expect(meeting.phase == phase)

        meeting.requestEnd()
        await meeting.confirmEnd()?.value
        #expect(meeting.page == .review)
        #expect(meeting.phase == .idle)
        #expect(!meeting.showsEndConfirmation)
        #expect(meeting.store.finals.first?.text == "Keep after cancelling")
    }

    @Test func endingIsNotOfferedOutsideALiveMeeting() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.requestEnd()
        #expect(!meeting.showsEndConfirmation, "Preparation has nothing to end")

        meeting.consentConfirmed = true
        await meeting.start()
        fixture.system.stopError = .stop
        await meeting.end()
        #expect(meeting.phase == .stopping)
        meeting.requestEnd()
        #expect(!meeting.showsEndConfirmation, "A failed stop is retried, not ended again")

        fixture.system.stopError = nil
        await meeting.retryStop()
        #expect(meeting.page == .review)
        meeting.requestEnd()
        #expect(!meeting.showsEndConfirmation, "A finished meeting cannot be ended twice")
    }

    @Test func pendingConfirmationIsDroppedWhenTheMeetingCanNoLongerEnd() async {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.requestEnd()
        #expect(meeting.showsEndConfirmation)

        fixture.system.stopError = .stop
        await meeting.pause()
        #expect(meeting.phase == .stopping)
        #expect(meeting.confirmEnd() == nil)
        #expect(!meeting.showsEndConfirmation)
        #expect(meeting.page == .live)

        fixture.system.stopError = nil
        await meeting.retryStop()
        await meeting.end()
    }
}

@MainActor
@Suite
struct InsightReviewBadgeTests {
    @Test func confirmedCandidateIsPositiveNotAWarning() {
        let badge = InsightReviewBadge(review: .confirmed, status: .complete)
        #expect(badge.text == "確認済み")
        #expect(badge.symbol == "checkmark.circle")
        #expect(badge.tone == .positive)
        #expect(badge.color == DesignTokens.positive)
        #expect(badge.color != DesignTokens.warning)
    }

    @Test func rejectedCandidateIsNeutralWithACross() {
        let badge = InsightReviewBadge(review: .rejected, status: .complete)
        #expect(badge.text == "却下")
        #expect(badge.symbol == "xmark.circle")
        #expect(badge.tone == .neutral)
        #expect(badge.color == DesignTokens.secondary)
    }

    @Test func unreviewedCandidateStillAsksForAttention() {
        let badge = InsightReviewBadge(review: .unreviewed, status: .complete)
        #expect(badge.text == "未確認")
        #expect(badge.symbol == "questionmark.circle")
        #expect(badge.tone == .attention)
        #expect(badge.color == DesignTokens.warning)
    }

    @Test func cardsOutsideReviewShowTheirGenerationState() {
        let generating = InsightReviewBadge(review: nil, status: .generating)
        #expect(generating.text == "生成中・未検証")
        #expect(generating.symbol == "ellipsis.circle")
        #expect(generating.tone == .neutral)

        let interrupted = InsightReviewBadge(review: nil, status: .interrupted)
        #expect(interrupted.text == "中断")
        #expect(interrupted.symbol == "exclamationmark.triangle")
        #expect(interrupted.tone == .attention)

        let complete = InsightReviewBadge(review: nil, status: .complete)
        #expect(complete.text == "要確認")
        #expect(complete.symbol == "questionmark.circle")
        #expect(complete.tone == .attention)
    }

    @Test func reviewStatesAreDistinguishableWithoutColour() {
        let symbols = MeetingCandidate.Review.allCases.map { InsightReviewBadge(review: $0, status: .complete).symbol }
        #expect(Set(symbols).count == MeetingCandidate.Review.allCases.count)
    }
}

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct DesignReviewSmallFixViewTests {
    @Test(arguments: [false, true])
    func endButtonAsksBeforeEndingAndSitsApart(paused: Bool) async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller())
        meeting.consentConfirmed = true
        await meeting.start()
        if paused { await meeting.pause() }
        let host = NSHostingView(rootView: MeetingTransport(meeting: meeting))
        let window = makeWindow(host, width: 900, height: 160)
        defer { window.close() }
        await layout(host)

        let end = try #require(button("会議を終了", in: host))
        let neighbour = try #require(button(paused ? "再開" : "一時停止", in: host))
        let endFrame = try #require(frame(end))
        let neighbourFrame = try #require(frame(neighbour))
        let gap = endFrame.minX - neighbourFrame.maxX
        #expect(gap >= 12, "Ending must sit apart from the neighbouring control, gap \(gap)")
        if paused {
            let back = try #require(button("準備へ戻る", in: host))
            let backFrame = try #require(frame(back))
            let ordinary = neighbourFrame.minX - backFrame.maxX
            #expect(gap > ordinary + 8, "Ending needs more room than ordinary controls: \(gap) vs \(ordinary)")
        }

        _ = end.perform(NSSelectorFromString("accessibilityPerformPress"))
        await layout(host)
        #expect(meeting.showsEndConfirmation)
        #expect(meeting.page == .live, "Pressing the button alone must not end the meeting")
        #expect(meeting.phase == (paused ? .idle : .listening))

        meeting.showsEndConfirmation = false
        await meeting.end()
    }

    @Test(arguments: [1180.0, 640.0])
    func navigationCallsSavedSessionsHistory(width: Double) async {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let host = NSHostingView(rootView: AppShellView(destination: .sessions, phase: .idle, navigate: { _ in }) {
            Color.clear
        })
        let window = makeWindow(host, width: width, height: 520)
        defer { window.close() }
        await layout(host)
        let shown = strings(host)
        #expect(shown.contains("履歴"))
        #expect(!shown.contains { $0.contains("保存") }, "The destination must not read as a save action or use the old name")
        #expect(!shown.contains("Sessions"))
    }

    @Test func savedSessionListAndDetailUseTheSameName() async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let list = NSHostingView(rootView: SessionsView(library: SessionsLibrary(files: SessionFiles(directory: root)), fontSize: 16))
        let listWindow = makeWindow(list, width: 900, height: 520)
        defer { listWindow.close() }
        await layout(list)
        let listed = strings(list)
        #expect(listed.contains("履歴"))
        #expect(!listed.contains("保存したセッション"))
        #expect(!listed.contains("ライブラリ"), "The saved sessions list must not be confused with the knowledge library")

        let saved = SavedSession(version: 1, createdAt: Date(), updatedAt: Date(), snapshot: sessionFixture(title: "Design"))
        let detail = NSHostingView(rootView: SavedSessionView(saved: saved, fontSize: 16, back: {}, delete: {}))
        let detailWindow = makeWindow(detail, width: 900, height: 520)
        defer { detailWindow.close() }
        await layout(detail)
        let detailed = strings(detail)
        #expect(detailed.contains("履歴"))
        #expect(!detailed.contains("Sessions"))
    }

    @Test func topBarCallsSavedSessionsHistory() async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let suite = "DesignReviewSmallFix-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let composition = AppComposition(arguments: ["--ui-preview"], defaults: defaults)
        composition.navigation.request(.sessions, phase: .idle)
        try #require(composition.navigation.destination == .sessions)
        let host = NSHostingView(rootView: ContentView(composition: composition))
        let window = makeWindow(host, width: 1180, height: 780)
        defer { window.close() }
        await layout(host)
        let shown = strings(host)
        #expect(shown.contains("履歴"))
        #expect(!shown.contains("Sessions"))
        #expect(!shown.contains("保存したセッション"))
    }

    @Test func liveMeetingHeaderDoesNotNameAnUnavailablePreset() async throws {
        let release = TestAccessibility.shared.enable()
        defer { release() }
        let suite = "DesignReviewSmallFix-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let meeting = MeetingPreview.make(activity: AudioInputUse(), defaults: defaults)
        meeting.consentConfirmed = true
        await meeting.start()
        let host = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}))
        let window = makeWindow(host, width: 1180, height: 780)
        defer { window.close() }
        await layout(host)
        let shown = strings(host).joined(separator: "\n")
        #expect(shown.contains("Meeting / ライブ"))
        #expect(!shown.contains("General"))
        await meeting.end()
    }

    private func makeWindow(_ host: NSView, width: Double, height: Double) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

    private func value(_ name: String, of element: NSObject) -> Any? {
        guard element.responds(to: NSSelectorFromString(name)) else { return nil }
        return element.value(forKey: name)
    }

    private func elements(_ root: NSObject) -> [NSObject] {
        [root] + (value("accessibilityChildren", of: root) as? [NSObject] ?? []).flatMap { elements($0) }
    }

    /// 画面上の各要素が読み上げ・表示に使う文字列。
    private func strings(_ root: NSObject) -> [String] {
        elements(root).flatMap { element in
            ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { value($0, of: element) as? String }
        }
    }

    private func button(_ title: String, in root: NSObject) -> NSObject? {
        let press = NSSelectorFromString("accessibilityPerformPress")
        return elements(root).first { element in
            element.responds(to: press) && (value("accessibilityLabel", of: element) as? String == title
                || value("accessibilityTitle", of: element) as? String == title)
        }
    }

    private func frame(_ element: NSObject) -> NSRect? {
        (value("accessibilityFrame", of: element) as? NSValue)?.rectValue
    }
}
