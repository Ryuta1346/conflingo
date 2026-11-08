import AppKit
import Testing
@testable import ConfLingo

@MainActor
struct WindowCloseGuardTests {
    @Test func closeRequestReceivesItsWindowAndCanVeto() {
        let window = NSWindow()
        let delegate = WindowCloseGuard.CloseDelegate()
        var requestedWindow: NSWindow?
        delegate.shouldClose = { sender in
            requestedWindow = sender
            return false
        }
        #expect(!delegate.windowShouldClose(window))
        #expect(requestedWindow === window)
        delegate.shouldClose = { _ in true }
        #expect(delegate.windowShouldClose(window))
    }

    @Test func originalDelegateCanStillVetoClosing() {
        let window = NSWindow()
        let original = RejectCloseDelegate()
        let delegate = WindowCloseGuard.CloseDelegate()
        delegate.original = original
        delegate.shouldClose = { _ in true }
        #expect(!delegate.windowShouldClose(window))
    }
}

@MainActor
private final class RejectCloseDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool { false }
}
