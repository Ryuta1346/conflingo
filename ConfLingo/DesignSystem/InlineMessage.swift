import SwiftUI

struct InlineMessage: View {
    let message: UserMessage
    @State private var showsDetails = false

    init(_ message: UserMessage) { self.message = message }
    init(_ kind: UserMessage.Kind, _ text: String, details: String? = nil) {
        message = UserMessage(kind, text, details: details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.small) {
            Label {
                Text(message.text).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: message.kind.symbol).accessibilityHidden(true)
            }
            .foregroundStyle(message.kind.color)
            if let details = message.details {
                DisclosureGroup("詳細", isExpanded: $showsDetails) {
                    Text(details).font(DesignTokens.Typography.supporting)
                        .foregroundStyle(DesignTokens.text).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(DesignTokens.Typography.body)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .onChange(of: message) { showsDetails = false }
    }
}

extension UserMessage.Kind {
    var symbol: String {
        switch self {
        case .information: "info.circle"
        case .success: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .failure: "xmark.octagon"
        }
    }
    var color: Color {
        switch self {
        case .information: DesignTokens.secondary
        case .success: DesignTokens.positive
        case .warning: DesignTokens.warning
        case .failure: DesignTokens.danger
        }
    }
}
