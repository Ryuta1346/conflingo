import SwiftUI

struct MeetingTransport: View {
    @Bindable var meeting: MeetingWorkspace
    var menuRequestsEnd: Binding<Bool> = .constant(false)
    @State private var asksToEnd = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { inputStatus; Spacer(); controls }
                VStack(alignment: .leading, spacing: 10) { inputStatus; controls }
            }
            if meeting.phase == .idle, meeting.page != .review, let reason = meeting.startUnavailableReason {
                Text(reason).font(DesignTokens.Typography.supporting)
            }
            if meeting.phase == .preparing {
                Text(meeting.controller.preparation).font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.surface)
        .onChange(of: menuRequestsEnd.wrappedValue) { _, requested in
            guard requested else { return }
            meeting.requestEnd()
            asksToEnd = meeting.showsEndConfirmation
            menuRequestsEnd.wrappedValue = false
        }
        .alert("会議を終了しますか？", isPresented: endConfirmation) {
            Button("キャンセル", role: .cancel, action: meeting.cancelEnd)
            Button("会議を終了", role: .destructive) { meeting.confirmEnd() }
        } message: {
            Text("終了すると、この会議の文字起こしは再開できません。ここまでの発話とAIの回答は振り返りに残り、保存とMarkdownの書き出しができます。")
        }
    }

    /// 確認は終了ボタンを押した窓（メイン画面または小窓）に出す。メイン画面を隠した小窓からも終了できるようにするため。
    /// 表示の解除では確認状態を変えない。確定・取消の処理が、ダイアログを閉じる順序に左右されないようにする。
    private var endConfirmation: Binding<Bool> {
        Binding(get: { asksToEnd && meeting.showsEndConfirmation }, set: { if !$0 { asksToEnd = false } })
    }

    private var inputStatus: some View {
        HStack(spacing: 12) {
            ForEach([AudioOrigin.microphone, .systemAudio], id: \.self) { origin in
                Label("\(origin.label) \(state(origin))", systemImage: origin == .microphone ? "mic" : "speaker.wave.2")
                    .foregroundStyle(meeting.controller.inputState(origin) == .running ? DesignTokens.positive : DesignTokens.secondary)
            }
        }
        .font(DesignTokens.Typography.supporting)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var controls: some View {
        if meeting.page == .review {
            Button("新しい会議", action: meeting.requestDiscard)
        } else if meeting.phase == .stopping {
            if meeting.isBusy {
                ProgressView().controlSize(.small)
                Text("停止中…").font(DesignTokens.Typography.body)
            } else {
                Button("停止を再試行") { Task { await meeting.retryStop() } }
                    .buttonStyle(AppButtonStyle())
            }
        } else if meeting.phase == .preparing || meeting.isStarting {
            ProgressView().controlSize(.small)
            Button("準備を取り消す") { Task { await meeting.cancelPreparation() } }
                .disabled(meeting.isTransitioning)
        } else if meeting.phase == .listening {
            HStack(spacing: Self.endSpacing) {
                Button("一時停止", systemImage: "pause") { Task { await meeting.pause() } }
                endButton
            }
            .disabled(meeting.isBusy)
        } else {
            HStack(spacing: Self.endSpacing) {
                HStack {
                    if meeting.page == .live { Button("準備へ戻る", action: meeting.editPreparation) }
                    Button(meeting.page == .setup ? "会議を開始" : "再開", systemImage: "play") {
                        Task { await meeting.start() }
                    }
                    .buttonStyle(AppButtonStyle(.primary))
                    .disabled(!meeting.canStart)
                }
                if meeting.page == .live { endButton.disabled(!meeting.canEnd) }
            }
        }
    }

    /// 終了は取り消せないため、隣の操作から離して右端に置く。
    private static let endSpacing: CGFloat = 24

    private var endButton: some View {
        Button("会議を終了", systemImage: "stop", role: .destructive) {
            meeting.requestEnd()
            asksToEnd = meeting.showsEndConfirmation
        }
        .buttonStyle(AppButtonStyle(.destructive))
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
