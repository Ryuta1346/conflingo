import AppKit
import SwiftUI

struct CommandWindowScope: NSViewRepresentable {
    let router: AppCommandRouter
    let actions: AppCommandRouter.Actions

    func makeNSView(context: Context) -> ScopeView { ScopeView(router: router, actions: actions) }
    func updateNSView(_ view: ScopeView, context: Context) { view.update(actions) }
    static func dismantleNSView(_ view: ScopeView, coordinator: ()) { view.detach() }

    final class ScopeView: NSView {
        private let router: AppCommandRouter
        private var actions: AppCommandRouter.Actions
        private weak var registeredWindow: NSWindow?

        init(router: AppCommandRouter, actions: AppCommandRouter.Actions) {
            self.router = router
            self.actions = actions
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let window else { return }
            registeredWindow = window
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(focusChanged), name: name, object: window)
            }
            update(actions)
        }

        func update(_ actions: AppCommandRouter.Actions) {
            self.actions = actions
            // SwiftUI may update this view while evaluating the command menu.
            Task { @MainActor [weak self] in
                guard let self, let window = registeredWindow else { return }
                router.update(window, actions: self.actions)
            }
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            if let registeredWindow { router.remove(registeredWindow) }
            registeredWindow = nil
        }

        @objc private func focusChanged() { router.focusChanged() }
    }
}
