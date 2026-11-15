import SwiftUI

struct MeetingAIControls: View {
    @Bindable var meeting: MeetingWorkspace

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                MeetingAISettings(meeting: meeting, openResearch: { meeting.research.open("") })
                if meeting.page != .review { MeetingQuestionComposer(meeting: meeting) }
                ForEach(meeting.research.answers.reversed()) { answer in
                    AssistanceAnswerView(answer: answer, events: meeting.store.finals,
                        research: { meeting.research.open($0, evidenceIDs: answer.evidenceIDs) })
                }
            }
        }
    }
}

struct MeetingQuestionComposer: View {
    @Bindable var meeting: MeetingWorkspace
    var openDocuments: (() -> Void)?
    var scrollProxy: ScrollViewProxy?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                TextField("会話や資料について質問する", text: $meeting.assistanceDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4)
                    .accessibilityLabel("AIへの質問")
                    .modifier(RevealOnFocus(proxy: scrollProxy))
                Button("質問する", systemImage: "paperplane") {
                    let question = meeting.assistanceDraft
                    Task { await meeting.askAssistance(question) }
                }
                .buttonStyle(AppButtonStyle(.primary))
                .disabled(!meeting.canAskAssistance || meeting.assistanceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || meeting.assistanceDraft.count > 2_000)
                .modifier(RevealOnFocus(proxy: scrollProxy))            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { actions }
                VStack(alignment: .leading, spacing: 10) { actions }
            }
            if meeting.assistanceDraft.count > 2_000 { Text("質問は2,000文字以内で入力してください。").font(DesignTokens.Typography.supporting) }
            InlineMessage(meeting.ai.statusMessage)
                .accessibilityLabel("AI状態：\(meeting.ai.statusText)")
        }
    }

    @ViewBuilder private var actions: some View {
        if let openDocuments {
            Button("資料（\(meeting.knowledge.documents.count)）", systemImage: "books.vertical", action: openDocuments)
                .modifier(RevealOnFocus(proxy: scrollProxy))
        }
        WebResearchControls(research: meeting.research, language: meeting.answerLanguage,
            enabled: meeting.phase != .stopping && meeting.phase != .preparing && meeting.page != .review, showsAnswers: false, scrollProxy: scrollProxy)
        if meeting.ai.permitted {
            Button("AI送信を停止", role: .cancel) { meeting.setAIAllowed(false) }
                .modifier(RevealOnFocus(proxy: scrollProxy))
        }
    }
}
