import SwiftUI

struct AppButtonStyle: ButtonStyle {
    enum Kind: CaseIterable { case primary, secondary, destructive, link }
    var kind: Kind = .secondary

    init(_ kind: Kind = .secondary) { self.kind = kind }

    func makeBody(configuration: Configuration) -> some View {
        AppButtonLabel(configuration: configuration,
                       kind: configuration.role == .destructive ? .destructive : kind)
    }
}

private struct AppButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let kind: AppButtonStyle.Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    private var foreground: Color {
        switch kind {
        case .primary: DesignTokens.onAccent
        case .secondary: DesignTokens.text
        case .destructive: DesignTokens.danger
        case .link: DesignTokens.accent
        }
    }

    var body: some View {
        configuration.label
            .font(DesignTokens.Typography.body.weight(kind == .primary ? .medium : .regular))
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .link ? 0 : DesignTokens.Space.medium)
            .padding(.vertical, DesignTokens.Space.small)
            .frame(minHeight: kind == .primary ? 40 : (kind == .link ? 24 : 32))
            .background(background, in: RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.controlRadius)
                    .strokeBorder(border, lineWidth: isFocused ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.controlRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }

    private var background: Color {
        switch kind {
        case .primary: DesignTokens.accent
        case .link: .clear
        case .secondary, .destructive: DesignTokens.surface
        }
    }

    private var border: Color {
        if isFocused { return DesignTokens.accent }
        switch kind {
        case .primary, .link: return .clear
        case .secondary: return DesignTokens.border
        case .destructive: return DesignTokens.danger
        }
    }
}
