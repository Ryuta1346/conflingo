import SwiftUI

struct MeetingTransport: View {
    @Bindable var meeting: MeetingWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { inputStatus; Spacer(); controls }
                VStack(alignment: .leading, spacing: 10) { inputStatus; controls }
            }
            if meeting.phase == .preparing {
                Text(meeting.controller.preparation).font(.caption).foregroundStyle(DesignTokens.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
    }

    private var inputStatus: some View {
        HStack(spacing: 12) {
            ForEach([AudioOrigin.microphone, .systemAudio], id: \.self) { origin in
                Label("\(origin.label) \(state(origin))", systemImage: origin == .microphone ? "mic" : "speaker.wave.2")
                    .foregroundStyle(meeting.controller.inputState(origin) == .running ? DesignTokens.positive : DesignTokens.secondary)
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        if meeting.page == .review {
            Button("新しい会議", action: meeting.requestDiscard)
        } else if meeting.phase == .stopping {
            if meeting.isBusy {
                ProgressView().controlSize(.small)
                Text("停止中…").font(.callout)
            } else {
                Button("停止を再試行") { Task { await meeting.retryStop() } }
                    .buttonStyle(.borderedProminent)
            }
        } else if meeting.phase == .preparing || meeting.isStarting {
            ProgressView().controlSize(.small)
            Button("準備を取り消す") { Task { await meeting.cancelPreparation() } }
                .disabled(meeting.isTransitioning)
        } else if meeting.phase == .listening {
            HStack {
                Button("一時停止", systemImage: "pause") { Task { await meeting.pause() } }
                Button("会議を終了", systemImage: "stop") { Task { await meeting.end() } }
                    .tint(DesignTokens.danger)
            }
            .disabled(meeting.isBusy)
        } else {
            HStack {
                if meeting.page == .live {
                    Button("準備へ戻る", action: meeting.editPreparation)
                    Button("会議を終了") { Task { await meeting.end() } }
                }
                Button(meeting.page == .setup ? "会議を開始" : "再開", systemImage: "play") {
                    Task { await meeting.start() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!meeting.canStart)
            }
        }
    }

    private func state(_ origin: AudioOrigin) -> String {
        switch meeting.controller.inputState(origin) {
        case .idle: "停止"
        case .starting: "開始中"
        case .running: "取得中"
        case .stopping: meeting.isBusy ? "停止中" : "停止未完了"
        }
    }
}
