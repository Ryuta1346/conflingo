import AppKit
import SwiftUI

struct KnowledgeBodyView: NSViewRepresentable {
    let text: String
    let fontSize: Double

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = BodyScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let body = BodyTextView()
        body.isEditable = false
        body.isSelectable = true
        body.isRichText = false
        body.drawsBackground = false
        body.textColor = .labelColor
        body.isVerticallyResizable = true
        body.isHorizontallyResizable = false
        body.autoresizingMask = [.width]
        body.textContainerInset = NSSize(width: 4, height: 4)
        body.textContainer?.widthTracksTextView = true
        body.textContainer?.heightTracksTextView = false
        body.setAccessibilityLabel("資料本文")
        scroll.documentView = body
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let body = scroll.documentView as? NSTextView else { return }
        if body.string != text { body.string = text }
        let font = NSFont.systemFont(ofSize: fontSize)
        if body.font != font { body.font = font }
    }

    private final class BodyScrollView: NSScrollView {
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if window?.firstResponder === documentView {
                NSColor.keyboardFocusIndicatorColor.setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 4, yRadius: 4)
                ring.lineWidth = 2
                ring.stroke()
            }
        }
    }

    private final class BodyTextView: NSTextView {
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            enclosingScrollView?.needsDisplay = true
            return result
        }

        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            enclosingScrollView?.needsDisplay = true
            return result
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
                else { window?.selectNextKeyView(nil) }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
