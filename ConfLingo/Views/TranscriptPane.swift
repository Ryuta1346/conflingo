import SwiftUI

/// 字幕履歴を縦に流す1ペイン。dimmed エントリ（partial や未翻訳プレースホルダ）は薄く表示する。
struct TranscriptPane: View {
    struct Entry: Identifiable, Equatable {
        let id: String
        let text: String
        let dimmed: Bool
    }

    let title: String
    let entries: [Entry]
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(entries) { entry in
                        Text(entry.text)
                            .font(.system(size: fontSize))
                            .italic(entry.dimmed)
                            .foregroundStyle(entry.dimmed ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
