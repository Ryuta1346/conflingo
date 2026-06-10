import SwiftUI

/// 起動時チェック・音声認識モデルダウンロード中の画面。
struct SetupView: View {
    let availability: ModelAvailabilityService

    var body: some View {
        VStack(spacing: 16) {
            if availability.state == .downloadingSpeechModel {
                if let progress = availability.downloadProgress {
                    ProgressView(progress)
                        .frame(maxWidth: 320)
                } else {
                    ProgressView()
                }
                Text("英語音声認識モデルをダウンロードしています…")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("利用可能な機能を確認しています…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
