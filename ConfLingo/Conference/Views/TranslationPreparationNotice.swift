import SwiftUI

struct TranslationPreparationNotice: View {
    let state: TranslationCoordinator.PreparationState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                SessionErrorBanner(message: "翻訳モデルを準備できませんでした。文字起こしは引き続き利用できます。\n\(reason)")
                Button("翻訳を再試行", systemImage: "arrow.clockwise", action: retry)
                    .accessibilityHint("文字起こしを止めずに翻訳モデルの準備をやり直します")
            }
            .padding([.horizontal, .top], 16)
        case .preparing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("翻訳モデルを準備しています…").font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 16)
        case .idle, .ready:
            EmptyView()
        }
    }
}
