import SwiftUI

struct AppShellView<Content: View>: View {
    let destination: ConferenceNavigation.Destination
    let phase: SessionPhase
    let navigate: (ConferenceNavigation.Destination) -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            let layout = wide
                ? AnyLayout(HStackLayout(spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                Group {
                    if wide { sidebar } else { compactNavigation }
                }
                .frame(width: wide ? 184 : nil)
                Rectangle().fill(DesignTokens.border)
                    .frame(width: wide ? 1 : nil, height: wide ? nil : 1)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DesignTokens.canvas)
        .foregroundStyle(DesignTokens.text)
        .tint(DesignTokens.accent)
    }

    private var compactNavigation: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                navigationButton("ホーム", symbol: "house", target: .home)
                navigationButton("Conference", symbol: "captions.bubble", target: .setup)
                navigationButton("Meeting", symbol: "person.2", target: .meeting)
                navigationButton("保存", symbol: "folder", target: .sessions)
                navigationButton("資料", symbol: "books.vertical", target: .library)
                navigationButton("設定", symbol: "gearshape", target: .settings)
            }
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(12)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(DesignTokens.sidebar)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "captions.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.accent)
                Text("ConfLingo").font(.system(size: 17, weight: .semibold))
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 8)
            Text("ワークスペース")
                .font(.caption2)
                .foregroundStyle(DesignTokens.secondary)
                .padding(8)
            navigationButton("ホーム", symbol: "house", target: .home)
            navigationButton("Conference", symbol: "captions.bubble", target: .setup)
            navigationButton("Meeting", symbol: "person.2", target: .meeting)
            navigationButton("保存したセッション", symbol: "folder", target: .sessions)
            navigationButton("資料ライブラリ", symbol: "books.vertical", target: .library)
            Spacer()
            navigationButton("設定", symbol: "gearshape", target: .settings)
            Divider().padding(.vertical, 12)
            Label("音声認識は、このMacで。", systemImage: "checkmark.shield")
                .font(.caption2)
                .foregroundStyle(DesignTokens.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 12)
        .background(DesignTokens.sidebar)
    }

    private func navigationButton(
        _ title: String, symbol: String, target: ConferenceNavigation.Destination
    ) -> some View {
        let selected = destination == target || (target == .setup && destination == .live)
        return Button {
            if target == .setup && destination == .live { return }
            navigate(target)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .foregroundStyle(selected ? DesignTokens.accent : DesignTokens.text)
                .background(selected ? DesignTokens.surface : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(phase == .preparing || phase == .stopping)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
