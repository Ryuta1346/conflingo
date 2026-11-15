import SwiftUI

struct ConferenceAssistanceView: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    var livePanel = false
    var openDocuments: (() -> Void)?
    var close: (() -> Void)?
    @State private var showsSettings = false
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
        .sheet(isPresented: $showsSettings, onDismiss: { settingsFocused = true }) {
            ConferenceAssistanceSettings(workspace: workspace)
        }
    }

    private var answers: some View {
        VStack(alignment: .leading, spacing: 12) {
            if workspace.assistance.insights.isEmpty && workspace.research.answers.isEmpty {
                Text("提案はまだありません").font(DesignTokens.Typography.heading)
                Text("AIを使う場合は「AI設定」で送信範囲を確認してください。")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)
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
                        Text(event.text).lineLimit(2)
                        Button("Webで調べる") { workspace.research.open(event.text, evidenceIDs: [event.id]) }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(1)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                TextField("発話や資料について質問する", text: $workspace.assistanceDraft, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...4).accessibilityLabel("AIへの質問")
                Button("質問する") {
                    let question = workspace.assistanceDraft
                    Task { await workspace.askAssistance(question) }
                }
                .buttonStyle(AppButtonStyle(.primary))
                .disabled(!workspace.canAskAssistance || workspace.assistanceDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workspace.assistanceDraft.count > 2_000)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            if workspace.assistanceDraft.count > 2_000 { Text("質問は2,000文字以内で入力してください。").font(DesignTokens.Typography.supporting) }
            InlineMessage(workspace.assistance.statusMessage)
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

struct ConferenceAssistanceSettings: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var showsConnection = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI設定・送信範囲").font(DesignTokens.Typography.title)
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(workspace.settings.selected.destinationLabel).font(DesignTokens.Typography.heading)
                    Button("LLM設定") { showsConnection = true }
                    Picker("回答言語", selection: $workspace.answerLanguage) {
                        ForEach(AnswerLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.onChange(of: workspace.answerLanguage) { workspace.cancel() }
                    Text("確定した発話（最大30件）と質問を\(workspace.settings.selected.name)へ送ります。資料の参照も許可した場合、関連する抜粋を最大5箇所送ります。音声は送りません。")
                        .font(DesignTokens.Typography.body)
                    Toggle("発話を使ったAI支援を許可", isOn: Binding(get: { workspace.assistance.permitted },
                        set: { workspace.setAssistancePermission($0) }))
                    Toggle("手動質問にも資料を使う", isOn: Binding(get: { workspace.knowledge.permitted },
                        set: { workspace.knowledge.setPermission($0) })).disabled(!workspace.assistance.permitted)
                    Toggle("自動提案を使う", isOn: Binding(get: { workspace.assistance.automaticEnabled },
                        set: { workspace.assistance.setAutomatic($0, after: workspace.assistanceStore.finals.last?.startOffset ?? 0) }))
                        .disabled(!workspace.assistance.permitted)
                    Toggle("自動提案にも資料を使う", isOn: Binding(get: { workspace.assistance.automaticKnowledgeEnabled },
                        set: { workspace.assistance.setAutomaticKnowledge($0) })).disabled(!workspace.assistance.automaticEnabled)
                    Text("送信先：\(workspace.settings.selected.baseURL)。料金・データ保持・学習への利用は接続先の契約をご確認ください。手動質問・自動提案・Web調査の許可は別々です。")
                        .font(DesignTokens.Typography.body).textSelection(.enabled)
                }.padding(1)
                .disabled(workspace.store.phase == .preparing || workspace.store.phase == .stopping)
            }
        }.sheetSurface().frame(minWidth: 480, idealWidth: 600, minHeight: 480, idealHeight: 640)
        .sheet(isPresented: $showsConnection) {
                LLMSettingsSheet(settings: workspace.settings) { showsConnection = false }
        }
    }
}
