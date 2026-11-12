import SwiftUI

/// Measure using the source's wrapping, reserving an extra line for language expansion.
struct ReservedTranslation<Content: View>: View {
    let sourceText: String
    let fontSize: Double
    @ViewBuilder var content: () -> Content

    var body: some View {
        TranslationReservationLayout(fontSize: fontSize) {
            Text(sourceText + "\n")
                .font(.system(size: fontSize)).lineSpacing(6)
                .hidden().accessibilityHidden(true)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TranslationReservationLayout: Layout {
    let fontSize: Double

    struct Cache {
        var width: CGFloat?
        var fontSize: Double = 0
        var height: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) {}

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        let height = max(CGFloat(fontSize * 2.8), sizes.map(\.height).max() ?? 0)
        if cache.width != width || cache.fontSize != fontSize {
            cache = Cache(width: width, fontSize: fontSize, height: height)
        } else {
            // A retry or a shorter completed translation must not pull later utterances up.
            cache.height = max(cache.height, height)
        }
        return CGSize(width: width, height: cache.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for view in subviews {
            view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}
