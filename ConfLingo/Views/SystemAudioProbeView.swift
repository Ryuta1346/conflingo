import SwiftUI

struct SystemAudioProbeView: View {
    @Bindable var controller: SystemAudioProbeController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("システム音声の確認")
                .font(.title2.bold())
            Text("Macで再生される音声が対象です。会議以外のアプリの音も含みます。ConfLingo自身の音とマイク音声は取得しません。")
                .foregroundStyle(.secondary)
            Text("画面映像・音声ファイルは保存せず、文字起こしや外部送信も行いません。")
                .font(.callout)

            LabeledContent("アクセス", value: permissionLabel)
            LabeledContent("状態", value: phaseLabel)
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: controller.level)
                    .accessibilityLabel("入力レベル")
                    .accessibilityValue("\(Int(controller.level * 100))パーセント")
                Text("受信フレーム数: \(controller.frameCount)")
                    .font(.callout.monospacedDigit())
            }

            if let error = controller.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack {
                Button("アクセスを確認") { Task { await controller.requestAccess() } }
                    .disabled(controller.phase != .idle)
                Spacer()
                if controller.phase == .idle {
                    Button("入力を開始") { Task { await controller.start() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(controller.phase == .starting ? "キャンセル" : "入力を停止") {
                        Task { await controller.stop() }
                    }
                }
            }
            Text("アクセス未許可の場合は、システム設定の「プライバシーとセキュリティ」から画面・システム音声の収録を許可してください。変更後は再起動が必要な場合があります。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { controller.refreshPermission() }
        .onDisappear {
            Task {
                await controller.stop()
                if controller.phase == .stopping { openWindow(id: "system-audio-probe") }
            }
        }
    }

    private var permissionLabel: String {
        switch controller.permission {
        case .granted: "許可済み"
        case .denied: "アクセス未許可"
        case .undetermined, .unknown: "未確認／アクセス未許可"
        }
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .idle: "停止中"
        case .starting: "開始準備中"
        case .running: "入力中"
        case .stopping: "停止処理中／失敗時は再試行してください"
        }
    }
}
