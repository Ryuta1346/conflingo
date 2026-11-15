import SwiftUI

struct SheetHeader: View {
    let title: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Space.large) {
            Text(title).font(DesignTokens.Typography.title).accessibilityAddTraits(.isHeader)
            Spacer(minLength: DesignTokens.Space.small)
            Button("閉じる", action: close).keyboardShortcut(.cancelAction)
        }
    }
}

extension View {
    func sheetSurface() -> some View {
        padding(DesignTokens.Space.extraLarge)
            .background(DesignTokens.canvas)
            .foregroundStyle(DesignTokens.text)
            .font(DesignTokens.Typography.body)
            .buttonStyle(AppButtonStyle())
    }
}

struct LLMSettingsSheet: View {
    let settings: LLMSettings
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Space.large) {
            SheetHeader(title: "LLM設定", close: close)
            ScrollView { LLMSettingsView(settings: settings).padding(1) }
        }
        .sheetSurface()
        .frame(minWidth: 360, idealWidth: 680, maxWidth: 680,
               minHeight: 320, idealHeight: 560, maxHeight: 560)
    }
}
