import AppKit
import SwiftUI

@MainActor
final class MeetingFloatingPanel: NSObject, NSWindowDelegate {
    private(set) var panel: NSPanel?
    weak var mainWindow: NSWindow?
    private let defaults: UserDefaults
    var expand: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func show(meeting: MeetingWorkspace, compactMain: Bool = false) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 120, y: 120, width: 420, height: 430),
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.title = "Meeting — 小窓"
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.minSize = NSSize(width: 360, height: 330)
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: MeetingFloatingView(
                meeting: meeting, defaults: defaults,
                expand: { [weak self] in self?.showMain() },
                hide: { [weak self] in self?.hide() }
            ))
            if let saved = defaults.string(forKey: "meetingPanelFrame") {
                panel.setFrame(NSRectFromString(saved), display: false)
            }
            self.panel = panel
        }
        guard let panel else { return }
        panel.setFrame(Self.constrained(panel.frame, to: NSScreen.screens.map(\.visibleFrame)), display: false)
        panel.orderFront(nil)
        if compactMain { mainWindow?.orderOut(nil) }
    }

    func showMain() {
        hide()
        expand?()
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func hide() { panel?.orderOut(nil) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
    func windowDidResize(_ notification: Notification) { saveFrame() }

    private func saveFrame() {
        if let panel { defaults.set(NSStringFromRect(panel.frame), forKey: "meetingPanelFrame") }
    }

    static func constrained(_ frame: NSRect, to screens: [NSRect]) -> NSRect {
        guard let screen = screens.first(where: { $0.intersects(frame) }) ?? screens.first else { return frame }
        let width = min(max(frame.width, 360), screen.width)
        let height = min(max(frame.height, 330), screen.height)
        return NSRect(x: min(max(frame.minX, screen.minX), screen.maxX - width),
                      y: min(max(frame.minY, screen.minY), screen.maxY - height), width: width, height: height)
    }
}

struct MeetingWindowAttachment: NSViewRepresentable {
    let floating: MeetingFloatingPanel
    func makeNSView(context: Context) -> Attachment { Attachment(floating: floating) }
    func updateNSView(_ view: Attachment, context: Context) {}

    final class Attachment: NSView {
        let floating: MeetingFloatingPanel
        init(floating: MeetingFloatingPanel) { self.floating = floating; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { floating.mainWindow = window }
        }
    }
}

private struct MeetingFloatingView: View {
    @Bindable var meeting: MeetingWorkspace
    @AppStorage private var fontSize: Double
    @AppStorage private var appearance: String
    let expand: () -> Void
    let hide: () -> Void

    init(meeting: MeetingWorkspace, defaults: UserDefaults, expand: @escaping () -> Void, hide: @escaping () -> Void) {
        self.meeting = meeting
        _fontSize = AppStorage(wrappedValue: 16, "fontSize", store: defaults)
        _appearance = AppStorage(wrappedValue: "system", "appearance", store: defaults)
        self.expand = expand
        self.hide = hide
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(meeting.title).font(.headline).lineLimit(1)
                Spacer()
                Button("展開", systemImage: "arrow.up.left.and.arrow.down.right", action: expand)
                Button("非表示", systemImage: "eye.slash", action: hide)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label(meeting.aiStatus, systemImage: "cloud").font(.caption)
                    if let error = meeting.controller.lastError { SessionErrorBanner(message: error) }
                    if let insight = MeetingInsight.featured(in: meeting.insights) {
                        MeetingInsightCard(meeting: meeting, insight: insight, fontSize: fontSize)
                        Button("発話をメイン画面で確認", action: expand)
                    } else {
                        Text(meeting.page == .review ? "会議を終了しました" : "AI提案はまだありません")
                            .font(.system(size: fontSize, weight: .semibold))
                        Text("発話はメイン画面で確認できます。")
                            .font(.callout).foregroundStyle(DesignTokens.secondary)
                    }
                    Text("非表示にしても音声収集は続きます。ウィンドウメニューから再表示できます。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                }
                .padding(14)
            }
            Divider()
            if meeting.page == .setup || meeting.page == .review {
                VStack(spacing: 8) {
                    Text("マイク 停止 · 内部音声 停止").font(.caption).foregroundStyle(DesignTokens.secondary)
                    Button(meeting.page == .setup ? "メイン画面で準備" : "振り返りを開く", action: expand)
                }
                .padding(14)
            } else {
                MeetingTransport(meeting: meeting)
            }
        }
        .background(DesignTokens.canvas)
        .foregroundStyle(DesignTokens.text)
        .tint(DesignTokens.accent)
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
    }
}
