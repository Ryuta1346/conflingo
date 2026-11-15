import SwiftUI

enum WorkspaceLayout {
    static let sidebarThreshold: CGFloat = 1024
    static let sidebarWidth: CGFloat = 184
    static let subtitleColumnsWidth: CGFloat = 820
    static let meetingColumnsWidth: CGFloat = 800
    static let assistanceWidth: CGFloat = 340

    static func docksAssistance(contentWidth: CGFloat) -> Bool {
        contentWidth >= subtitleColumnsWidth + assistanceWidth + 1
    }
}

/// Keep the same transcript view while moving Live suggestions above it at narrow widths.
struct MeetingPaneLayout: Layout {
    var horizontal: Bool
    var suggestionsFirst: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if horizontal {
            let transcriptWidth = (bounds.width - 16) * (suggestionsFirst ? 0.42 : 0.5)
            subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: transcriptWidth, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + transcriptWidth + 16, y: bounds.minY),
                proposal: ProposedViewSize(width: bounds.width - transcriptWidth - 16, height: bounds.height))
        } else {
            let height = (bounds.height - 12) / 2
            for index in 0..<2 {
                let row = suggestionsFirst ? 1 - index : index
                subviews[index].place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(row) * (height + 12)),
                    proposal: ProposedViewSize(width: bounds.width, height: height))
            }
        }
    }
}
