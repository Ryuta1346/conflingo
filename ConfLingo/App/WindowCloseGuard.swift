import AppKit
import SwiftUI

/// Intercepts only closing; the original SwiftUI delegate keeps its other responsibilities.
struct WindowCloseGuard: NSViewRepresentable {
    let shouldClose: (NSWindow) -> Bool

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView()
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.closeDelegate.shouldClose = shouldClose
        view.attach()
    }

    static func dismantleNSView(_ view: AttachmentView, coordinator: ()) {
        view.detach()
    }

    final class AttachmentView: NSView {
        let closeDelegate = CloseDelegate()
        private weak var attachedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attach()
        }

        func attach() {
            guard let window, window !== attachedWindow else { return }
            detach()
            attachedWindow = window
            closeDelegate.original = window.delegate
            window.delegate = closeDelegate
        }

        func detach() {
            if let attachedWindow, attachedWindow.delegate === closeDelegate {
                attachedWindow.delegate = closeDelegate.original
            }
            attachedWindow = nil
        }
    }

    final class CloseDelegate: NSObject, NSWindowDelegate {
        weak var original: (any NSWindowDelegate)?
        var shouldClose: ((NSWindow) -> Bool)?

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard shouldClose?(sender) ?? true else { return false }
            return original?.windowShouldClose?(sender) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
        }
    }
}
