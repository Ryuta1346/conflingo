import SwiftUI

struct SetupView: View {
    let state: ModelAvailabilityService.State
    let progress: Progress?
    let sourceLanguage: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 8) {
                if state == .downloadingSpeechModel {
                    Text("\(LanguageCatalog.displayName(for: sourceLanguage))の認識モデルを準備しています…")
                    if let progress { ProgressView(progress).frame(maxWidth: 320) }
                } else {
                    Text("利用できる言語とモデルを確認しています…")
                }
                Text("準備が完了してから、字幕を開始できます。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
            }
        }
        .font(.callout)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
