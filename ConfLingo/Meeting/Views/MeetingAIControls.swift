import SwiftUI

struct MeetingAIControls: View {
    @Bindable var meeting: MeetingWorkspace
    @State private var question = ""
    @State private var showsKeySettings = false
    @State private var showsDataDetails = true

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                #if DEBUG
                if meeting.previewUsesLiveAI {
                    Text("実API検証：合成発話・音声取得なし・選択したAIへ実通信（API利用料金が発生）")
                        .font(.caption).foregroundStyle(DesignTokens.warning)
                }
                #endif
                HStack {
                    Label(meeting.llmSettings.selected.destinationLabel, systemImage: "sparkles").font(.headline)
                    Spacer()
                    Button("LLM設定") { showsKeySettings = true }
                }
                Picker("AIの回答言語", selection: $meeting.answerLanguage) {
                    ForEach(AnswerLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                Text("質問や発話の言語に関係なく適用します。変更は次の回答から反映されます。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Toggle("確定発話と質問文を\(meeting.llmSettings.selected.name)へ送信することを許可", isOn: Binding(
                    get: { meeting.ai.permitted }, set: { meeting.setAIAllowed($0) }
                ))
                .disabled(meeting.page == .review || meeting.phase == .stopping)
                DisclosureGroup("送信する内容・データの扱い", isExpanded: $showsDataDetails) {
                Text("音声は送りません。手動質問では許可前を含む直近の確定発話を最大30件送ります。資料は手動質問・自動提案それぞれの許可、または終了後要約の確認画面で選択した場合に参照します。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Text("送信先：\(meeting.llmSettings.selected.baseURL)。料金・データ保持・学習への利用は、接続先サービスとご自身の契約・実行環境の条件をご確認ください。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                }
                Toggle("自動提案を使う（追加のAI処理が発生）", isOn: Binding(
                    get: { meeting.ai.automaticEnabled }, set: { meeting.setAutomaticAI($0) }
                ))
                .disabled(!meeting.ai.permitted || meeting.ai.subscriptionFailed || meeting.page == .review || meeting.phase == .stopping)
                Toggle("自動提案にも資料を使う", isOn: Binding(
                    get: { meeting.ai.automaticKnowledgeEnabled }, set: { meeting.setAutomaticKnowledgeAllowed($0) }
                ))
                .disabled(!meeting.ai.permitted || !meeting.ai.automaticEnabled || meeting.page == .review || meeting.phase == .stopping || meeting.knowledge.isBusy)
                Text("発話に関連する資料を検索し、最大5箇所・6,000文字と資料名・位置を送ります。提案の回数上限は同じですが、入力トークンが増える場合があります。手動質問・終了後要約の資料許可とは別の設定です。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if meeting.page != .review {
                    TextField("会話や資料について質問する", text: $question, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .accessibilityLabel("AIへの質問")
                    HStack {
                        Button("Ask AI", systemImage: "paperplane") {
                            let value = question
                            Task { await meeting.askAssistance(value) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!meeting.canAskAssistance || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 2_000)
                        if meeting.ai.permitted {
                            Button("AI送信を停止", role: .cancel) { meeting.setAIAllowed(false) }
                        }
                    }
                    if question.count > 2_000 { Text("質問は2,000文字以内で入力してください。").font(.caption) }
                }
                WebResearchControls(research: meeting.research, language: meeting.answerLanguage,
                    enabled: meeting.phase != .stopping && meeting.phase != .preparing && meeting.page != .review)
                Label(meeting.ai.statusText, systemImage: meeting.ai.state == .sending ? "arrow.up.circle" : "cloud")
                    .font(.caption).accessibilityLabel("AI状態：\(meeting.ai.statusText)")
                if meeting.page != .review {
                    Text(meeting.ai.contextDescription).font(.caption).foregroundStyle(DesignTokens.secondary)
                    if let usage = meeting.ai.lastUsage {
                        Text("直近の使用量：入力 \(usage.inputTokens)・出力 \(usage.outputTokens + usage.thinkingTokens) トークン（思考を含む）")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                    }
                }
            }
        }
        .onChange(of: meeting.ai.permitted) { _, allowed in
            if allowed { showsDataDetails = false }
        }
        .sheet(isPresented: $showsKeySettings) {
            VStack(alignment: .trailing, spacing: 16) {
                LLMSettingsView(settings: meeting.llmSettings)
                Button("閉じる") { showsKeySettings = false }.keyboardShortcut(.cancelAction)
            }
            .padding(24).frame(width: 680)
        }
    }
}
