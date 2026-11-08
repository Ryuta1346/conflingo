import SwiftUI

struct DualTranscriptionProbeView: View {
    @Bindable var controller: DualTranscriptionController
    @Environment(\.openWindow) private var openWindow
    @State private var microphoneLocale = initialLocale
    @State private var systemLocale = initialLocale
    @State private var fastResults = false

    private static var initialLocale: String {
        let current = UserDefaults.standard.string(forKey: "sourceLocaleID") ?? "en-US"
        return Locale(identifier: current).language.languageCode?.identifier == "ja" ? "ja-JP" : "en-US"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("2入力文字起こしの確認").font(.title2.bold())
            Text("マイクとMacの内部音声を別々に文字起こしします。内部音声には会議以外のアプリの音も含まれます。入力元は人物名を示しません。回り込みを減らすにはヘッドフォンを使ってください。")
                .font(.callout).foregroundStyle(.secondary)
            Text("音声ファイルの保存・外部AI送信は行いません。開始時に認識モデルのダウンロードとアクセス許可が必要な場合があります。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                inputSettings(.microphone, selection: $microphoneLocale)
                inputSettings(.systemAudio, selection: $systemLocale)
            }
            Toggle("高速確定（精度低め）", isOn: $fastResults)
                .disabled(controller.phase != .idle)
            HStack {
                Text(phaseLabel).font(.callout)
                Spacer()
                Button("Clear") { controller.clear() }.disabled(controller.phase != .idle)
                if controller.phase == .idle {
                    Button("2入力を開始") {
                        Task {
                            await controller.start(
                                microphoneLocale: Locale(identifier: microphoneLocale),
                                systemLocale: Locale(identifier: systemLocale), fastResults: fastResults
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(controller.phase == .preparing ? "キャンセル" : "停止／停止を再試行") {
                        Task { await controller.stop() }
                    }
                }
            }
            if controller.phase == .idle, controller.activity.owner != nil {
                Text(controller.activity.busyMessage).font(.callout).foregroundStyle(.secondary)
            }
            if let error = controller.lastError {
                Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if controller.store.finals.isEmpty && controller.store.partials.isEmpty {
                        Text("認識した発話を、入力元と会議の経過時刻付きで表示します。")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(controller.store.finals) { event in transcript(event) }
                    ForEach(controller.store.partials) { event in transcript(event) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("時刻は各入力の開始通知を基準にしています。実音声での同期精度・認識精度は検証が必要です。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { controller.refreshPermissions() }
        .onDisappear {
            Task {
                await controller.stop()
                if controller.phase == .stopping { openWindow(id: "dual-transcription-probe") }
            }
        }
    }

    private func inputSettings(_ origin: AudioOrigin, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(origin.label, selection: selection) {
                Text("日本語").tag("ja-JP")
                Text("英語").tag("en-US")
            }
            .disabled(controller.phase != .idle)
            Text("アクセス：\(permissionLabel(origin))")
                .font(.caption).foregroundStyle(.secondary)
            Text(inputStateLabel(origin))
                .font(.caption).foregroundStyle(.secondary)
            if controller.permissions[origin] != .granted {
                Text(origin == .microphone
                     ? "許可の変更：システム設定 → プライバシーとセキュリティ → マイク"
                     : "許可の変更：システム設定 → プライバシーとセキュリティ → 画面収録とシステムオーディオ録音。変更後は再起動が必要な場合があります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcript(_ event: TranscriptEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(event.origin.label) · \(event.startOffset, specifier: "%.1f")秒 · \(event.isFinal ? "確定" : "認識中")")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(event.text).textSelection(.enabled)
                .foregroundStyle(event.isFinal ? .primary : .secondary)
        }
    }

    private func permissionLabel(_ origin: AudioOrigin) -> String {
        switch controller.permissions[origin] {
        case .granted: "許可済み"
        case .denied: "未許可（システム設定を確認してください）"
        case .undetermined, .unknown, nil: "未確認／未許可"
        }
    }

    private func inputStateLabel(_ origin: AudioOrigin) -> String {
        switch controller.inputState(origin) {
        case .idle: "入力停止中"
        case .starting: "入力開始処理中"
        case .running: "入力開始済み"
        case .stopping: "終了処理中／停止失敗時は再試行が必要です"
        }
    }

    private var phaseLabel: String {
        switch controller.phase {
        case .idle: "停止中"
        case .preparing: controller.preparation
        case .listening: "2入力の認識中"
        case .stopping: "停止処理中／失敗時は再試行してください"
        }
    }
}
