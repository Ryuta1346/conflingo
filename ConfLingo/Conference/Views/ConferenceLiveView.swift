import SwiftUI

struct ConferenceLiveView: View {
    @Bindable var store: SessionStore
    let sourceLanguage: String
    let targetLanguage: String?
    let profileName: String
    @Binding var fontSize: Double
    let editSettings: () -> Void
    let clear: () -> Void
    var corrections: [ConferenceCorrection] = []

    var body: some View {
        GeometryReader { geometry in
            let stacked = targetLanguage != nil && geometry.size.width < 820
            let minimumHeight = minimumPaneHeight * (stacked ? 2 : 1) + 160
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .center) {
                            heading
                            Spacer()
                            Button("字幕の設定", systemImage: "gearshape", action: editSettings)
                                .disabled(store.phase == .preparing || store.phase == .stopping)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            heading
                            Button("字幕の設定", systemImage: "gearshape", action: editSettings)
                                .disabled(store.phase == .preparing || store.phase == .stopping)
                        }
                    }
                    Group {
                        if targetLanguage == nil {
                            sourcePane
                        } else {
                            let horizontal = geometry.size.width >= 820
                            let layout = horizontal
                                ? AnyLayout(HStackLayout(spacing: 0))
                                : AnyLayout(VStackLayout(spacing: 0))
                            layout {
                                sourcePane
                                Rectangle().fill(DesignTokens.border)
                                    .frame(width: horizontal ? 1 : nil, height: horizontal ? nil : 1)
                                translationPane
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radius))
                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.radius).stroke(DesignTokens.border))
                    HStack {
                        Text("字幕を選択してコピーできます。")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                        Spacer()
                        Button("字幕を消去", systemImage: "trash", action: clear)
                            .disabled(store.phase != .idle || store.segments.isEmpty)
                    }
                }
                .frame(height: max(minimumHeight, geometry.size.height - (geometry.size.width < 820 ? 32 : 48)))
                .padding(geometry.size.width < 820 ? 16 : 24)
            }
        }
    }

    private var minimumPaneHeight: CGFloat { 44 + max(160, fontSize * 4) }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.sessionName.isEmpty ? "Conference" : store.sessionName)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text("\(LanguageCatalog.displayName(for: sourceLanguage))\(targetLanguage.map { " → " + LanguageCatalog.displayName(for: $0) } ?? " · 文字起こしのみ") · 辞書：\(profileName)")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
                .lineLimit(2)
        }
    }

    private var sourcePane: some View {
        TranscriptPane(title: "原文 · \(LanguageCatalog.displayName(for: sourceLanguage))",
                       entries: TranscriptPresentation.source(store, corrections: corrections), fontSize: fontSize)
            .frame(minWidth: 220, minHeight: minimumPaneHeight)
    }

    private var translationPane: some View {
        TranscriptPane(title: "翻訳 · \(LanguageCatalog.displayName(for: targetLanguage ?? "ja"))",
                       entries: TranscriptPresentation.translation(store, corrections: corrections), fontSize: fontSize)
            .frame(minWidth: 220, minHeight: minimumPaneHeight)
    }
}
