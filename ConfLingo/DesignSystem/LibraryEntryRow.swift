import SwiftUI

struct LibraryEntryRow<Actions: View>: View {
    let title: String
    let symbol: String
    let subtitle: String
    var detail: String?
    var failure: String?
    let open: () -> Void
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol).foregroundStyle(DesignTokens.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(DesignTokens.Typography.heading).lineLimit(3)
                        Text(subtitle).font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                        if let detail {
                            Text(detail).font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(DesignTokens.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(12).contentShape(Rectangle())
            }
            .buttonStyle(AppButtonStyle()).disabled(failure != nil)
            .accessibilityLabel("\(title)を開く")
            .accessibilityHint([subtitle, detail].compactMap { $0 }.joined(separator: "。"))
            if let failure {
                InlineMessage(.failure, "保存内容を読み込めません。元の保存データは保持しています。", details: failure)
            }
            HStack { Spacer(minLength: 0); actions }
        }
    }
}
