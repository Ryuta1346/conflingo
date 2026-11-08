import SwiftUI

struct ControlBar: View {
    let phase: SessionPhase
    let isStopping: Bool
    let canStart: Bool
    let hasTranscript: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            StatusLabel(text: status, symbol: phase == .listening ? "mic.fill" : "mic",
                        color: phase == .listening ? DesignTokens.positive : DesignTokens.secondary)
            Text("オンデバイス処理")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            Spacer(minLength: 8)
            switch phase {
            case .idle:
                Button(hasTranscript ? "字幕を再開" : "字幕を開始", systemImage: "play.fill", action: start)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!canStart)
            case .preparing:
                ProgressView().controlSize(.small)
                Button("開始準備中…") {}.disabled(true)
            case .listening:
                Button("停止する", systemImage: "stop.fill", action: stop)
                    .tint(DesignTokens.danger)
                    .buttonStyle(.bordered)
                    .keyboardShortcut("r", modifiers: .command)
            case .stopping:
                Button(isStopping ? "停止処理中…" : "停止を再試行", action: stop)
                    .disabled(isStopping)
                    .tint(DesignTokens.danger)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(DesignTokens.surface)
    }

    private var status: String {
        switch phase {
        case .idle: "マイク 停止中"
        case .preparing: "マイク 準備中"
        case .listening: "マイク 取得中"
        case .stopping: isStopping ? "マイク 停止処理中" : "マイク 停止未確認"
        }
    }
}
