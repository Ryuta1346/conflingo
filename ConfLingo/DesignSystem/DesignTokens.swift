import AppKit
import SwiftUI

enum DesignTokens {
    static let accent = Color(light: 0x315BD6, dark: 0x9BB5FF)
    static let canvas = Color(light: 0xF5F6F8, dark: 0x16191F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x20252D)
    static let sidebar = Color(light: 0xEDEFF3, dark: 0x1B1F26)
    static let border = Color(light: 0xDCE1E8, dark: 0x39414E)
    static let positive = Color(light: 0x246A52, dark: 0x8ED9B4)
    static let warning = Color(light: 0x875A19, dark: 0xF0C37B)
    static let danger = Color(light: 0xAE3D46, dark: 0xFFACB2)
    static let text = Color(light: 0x202631, dark: 0xEEF1F6)
    static let secondary = Color(light: 0x626C7C, dark: 0xA8B2C2)
    static let radius: CGFloat = 12
    static let spacing: CGFloat = 24
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 255) / 255,
                green: CGFloat((value >> 8) & 255) / 255,
                blue: CGFloat(value & 255) / 255,
                alpha: 1
            )
        })
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(DesignTokens.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radius))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.radius).stroke(DesignTokens.border))
    }
}

struct StatusLabel: View {
    let text: String
    let symbol: String
    var color: Color = DesignTokens.secondary

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var eyebrow: String = "Conference"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.caption).foregroundStyle(DesignTokens.secondary)
            Text(title).font(.system(size: 25, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(DesignTokens.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SessionErrorBanner: View {
    let message: String

    var body: some View {
        Label {
            Text(message).font(.callout).textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(DesignTokens.danger)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
