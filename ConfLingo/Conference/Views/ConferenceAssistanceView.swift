import SwiftUI

struct ConferenceAssistanceView: View {
    @Environment(\.readingFontSize) private var fontSize
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    var livePanel = false
    var openDocuments: (() -> Void)?
    var close: (() -> Void)?
    @State private var showsSettings = false
    @State private var pendingResearch = false
    @FocusState private var settingsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("AI支援").font(DesignTokens.Typography.heading)
                Spacer(minLength: 4)
                Button(workspace.assistance.permitted ? "AI設定 · 許可済み" : "AI設定 · オフ") { showsSettings = true }
                    .focused($settingsFocused)
                if let close {
                    Button(action: close) { Image(systemName: "xmark") }
                        .accessibilityLabel("AI支援を閉じる").keyboardShortcut(.cancelAction)
                }
            }
            if livePanel {
                ScrollView { answers }
                Divider()
            } else {
                answers
            }
            composer
        }
        .disabled(workspace.store.phase == .preparing || workspace.store.phase == .stopping)
        .sheet(isPresented: $showsSettings, onDismiss: {
            if pendingResearch { pendingResearch = false; workspace.research.open("") }
            else { settingsFocused = true }
        }) {
            ConferenceAssistanceSettings(workspace: workspace, openResearch: { pendingResearch = true; showsSettings = false })
        }
    }

    private var answers: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workspace.assistance.insights.isEmpty && workspace.research.answers.isEmpty && workspace.answers.isEmpty {
                Text("提案はまだありません").font(DesignTokens.Typography.heading)
                Text("AIを使う場合は「AI設定」で送信範囲を確認してください。")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)
            }
            if workspace.isGenerating, !workspace.preview.isEmpty {
                Text(workspace.preview).font(.system(size: fontSize)).textSelection(.enabled)
            }
            ForEach(workspace.answers.reversed()) { answer in
                VStack(alignment: .leading, spacing: 8) {
                    if answer.knowledgeReferences.isEmpty { InlineMessage(.warning, "資料根拠なし・要確認") }
                    AssistanceAnswerView(answer: answer, events: [])
                }
            }
            ForEach(workspace.assistance.insights.reversed()) { answer in
                AssistanceAnswerView(answer: answer, events: workspace.assistanceStore.finals,
                    research: { workspace.research.open($0, evidenceIDs: answer.evidenceIDs) })
            }
            ForEach(workspace.research.answers.reversed()) { answer in
                AssistanceAnswerView(answer: answer, events: workspace.assistanceStore.finals,
                    research: { workspace.research.open($0, evidenceIDs: answer.evidenceIDs) })
            }
            DisclosureGroup("発話からWebで調べる") {
                ForEach(workspace.assistanceStore.finals.suffix(30)) { event in
                    HStack {
                        Text(event.text).font(.system(size: fontSize)).lineLimit(2)
                        Button("Webで調べる") { workspace.research.open(event.text, evidenceIDs: [event.id]) }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(1)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("質問の対象", selection: $workspace.questionTarget) {
                ForEach(ConferenceKnowledgeWorkspace.QuestionTarget.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack(alignment: .bottom) {
                TextField("発話や資料について質問する", text: $workspace.questionDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4).accessibilityLabel("AIへの質問")
                Button("質問する") {
                    Task { await workspace.submitQuestion() }
                }
                .buttonStyle(AppButtonStyle(.primary))
                .disabled(!workspace.canSubmitQuestion)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            if workspace.questionDraft.count > 2_000 { Text("質問は2,000文字以内で入力してください。").font(DesignTokens.Typography.supporting) }
            if workspace.questionTarget == .documents {
                Text("資料のみを使います。許可はAI設定で確認できます。").font(DesignTokens.Typography.supporting)
                if !workspace.message.isEmpty { InlineMessage(.failure, workspace.message) }
                if workspace.isGenerating { Button("資料のAI処理を中断") { workspace.cancel() } }
            } else {
                InlineMessage(workspace.assistance.statusMessage)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if let openDocuments {
            Button("資料（\(workspace.knowledge.documents.count)）", action: openDocuments)
        }
        WebResearchControls(research: workspace.research, language: workspace.answerLanguage,
            enabled: workspace.canEditKnowledge, showsAnswers: false)
        if workspace.assistance.permitted {
            Button("AI送信を停止") { workspace.setAssistancePermission(false) }
        }
    }
}
