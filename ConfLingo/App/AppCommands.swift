import AppKit
import SwiftUI

@MainActor
struct SessionCommandActions {
    let title: String
    let canToggle: Bool
    let toggle: () -> Void
    var end: (() -> Void)?

    static func meeting(_ meeting: MeetingWorkspace, requestEnd: @escaping () -> Void) -> Self {
        let allowed = !meeting.isSavingSession && !meeting.isUsingLibrary && !meeting.isBusy
        return Self(title: meeting.phase == .listening ? "会議を一時停止" : meeting.page == .live ? "会議を再開" : "会議を開始",
            canToggle: allowed && (meeting.phase == .listening || meeting.canStart), toggle: {
                guard !meeting.isSavingSession, !meeting.isUsingLibrary, !meeting.isBusy else { return }
                if meeting.phase == .listening { Task { await meeting.pause() } }
                else if meeting.canStart { Task { await meeting.start() } }
            }, end: allowed && meeting.canEnd ? {
                guard meeting.canEnd, !meeting.isSavingSession, !meeting.isUsingLibrary else { return }
                requestEnd()
            } : nil)
    }
}

@MainActor
@Observable
final class AppCommandRouter {
    struct Actions {
        var session: SessionCommandActions?
        let fontSize: Binding<Double>
        let alwaysOnTop: Binding<Bool>
    }
    private final class Target {
        weak var window: NSWindow?
        var actions: Actions
        init(window: NSWindow, actions: Actions) { self.window = window; self.actions = actions }
    }
    private var targets: [ObjectIdentifier: Target] = [:]
    private(set) var revision = 0
    var showCompact: (() -> Void)?

    var active: Actions? {
        _ = revision
        guard let window = NSApp.keyWindow, window.attachedSheet == nil,
              let target = targets[ObjectIdentifier(window)], target.window === window else { return nil }
        return target.actions
    }

    func update(_ window: NSWindow, actions: Actions) {
        targets[ObjectIdentifier(window)] = Target(window: window, actions: actions)
    }
    func remove(_ window: NSWindow) { targets.removeValue(forKey: ObjectIdentifier(window)) }
    func focusChanged() { revision += 1 }
}

struct AppCommands: Commands {
    let router: AppCommandRouter

    var body: some Commands {
        CommandMenu("セッション") {
            Button(router.active?.session?.title ?? "開始／一時停止") {
                guard let action = router.active?.session, action.canToggle else { return }
                action.toggle()
            }.keyboardShortcut("r", modifiers: .command).disabled(router.active?.session?.canToggle != true)
            Button("会議を終了") { router.active?.session?.end?() }
                .keyboardShortcut("e", modifiers: [.command, .shift]).disabled(router.active?.session?.end == nil)
            Divider()
            Button("Meetingの小窓を表示") { router.showCompact?() }
                .disabled(router.showCompact == nil)
        }
        CommandGroup(after: .toolbar) {
            Button("読む文字を拡大") { resize(2) }.keyboardShortcut("=", modifiers: .command)
                .disabled(router.active == nil || (router.active?.fontSize.wrappedValue ?? 48) >= 48)
            Button("読む文字を拡大（＋）") { resize(2) }.keyboardShortcut("+", modifiers: .command)
                .disabled(router.active == nil || (router.active?.fontSize.wrappedValue ?? 48) >= 48)
            Button("読む文字を縮小") { resize(-2) }.keyboardShortcut("-", modifiers: .command)
                .disabled(router.active == nil || (router.active?.fontSize.wrappedValue ?? 10) <= 10)
            Toggle("ウィンドウを最前面に表示", isOn: Binding(
                get: { router.active?.alwaysOnTop.wrappedValue ?? false },
                set: { router.active?.alwaysOnTop.wrappedValue = $0 })).disabled(router.active == nil)
        }
    }

    private func resize(_ delta: Double) {
        guard let value = router.active?.fontSize else { return }
        value.wrappedValue = min(48, max(10, value.wrappedValue + delta))
    }
}
