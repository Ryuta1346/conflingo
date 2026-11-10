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
                    Text("実API検証：合成発話・音声取得なし・Geminiへ実通信（API利用料金が発生）")
                        .font(.caption).foregroundStyle(DesignTokens.warning)
                }
                #endif
                HStack {
                    Label("Gemini / 自分のAPIキー", systemImage: "sparkles").font(.headline)
                    Spacer()
                    Button("APIキー設定") { showsKeySettings = true }
                }
                Picker("AIの回答言語", selection: $meeting.answerLanguage) {
                    ForEach(AnswerLanguage.allCases, id: \.self) { language in
                        Text(language.label).tag(language)
                    }
                }
                Text("質問や発話の言語に関係なく適用します。変更は次の回答から反映されます。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Toggle("確定発話と質問文のGeminiへの送信を許可", isOn: Binding(
                    get: { meeting.ai.permitted }, set: { meeting.setAIAllowed($0) }
                ))
                .disabled(meeting.page == .review || meeting.phase == .stopping)
                DisclosureGroup("送信する内容・データの扱い", isExpanded: $showsDataDetails) {
                Text("音声は送りません。手動質問では許可前を含む直近の確定発話を最大30件送ります。資料は別の許可をオンにした手動質問だけで参照します。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Text("無料枠では入出力が製品改善に利用され得ます。有料枠でも限定的な保持があります。ご自身のGoogleプロジェクトの条件をご確認ください。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Link("Googleのデータ利用条件", destination: URL(string: "https://ai.google.dev/gemini-api/terms")!)
                    .font(.caption)
                }
                Toggle("自動提案を使う（追加のAPI利用が発生）", isOn: Binding(
                    get: { meeting.ai.automaticEnabled }, set: { meeting.setAutomaticAI($0) }
                ))
                .disabled(!meeting.ai.permitted || meeting.ai.subscriptionFailed || meeting.page == .review || meeting.phase == .stopping)
                if meeting.page == .live {
                    TextField("会話や資料について質問する", text: $question, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(2...4)
                        .accessibilityLabel("AIへの質問")
                    HStack {
                        Button("Ask AI", systemImage: "paperplane") {
                            let value = question
                            Task { await meeting.ai.ask(value) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!meeting.ai.canAsk || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 2_000)
                        if meeting.ai.permitted {
                            Button("AI送信を停止", role: .cancel) { meeting.setAIAllowed(false) }
                        }
                    }
                    if question.count > 2_000 { Text("質問は2,000文字以内で入力してください。").font(.caption) }
                }
                Label(meeting.ai.statusText, systemImage: meeting.ai.state == .sending ? "arrow.up.circle" : "cloud")
                    .font(.caption).accessibilityLabel("AI状態：\(meeting.ai.statusText)")
                if meeting.page == .live {
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
                GeminiKeySettingsView(credentials: meeting.credentials)
                Button("閉じる") { showsKeySettings = false }.keyboardShortcut(.cancelAction)
            }
            .padding(24).frame(width: 520)
        }
    }
}

struct GeminiKeySettingsView: View {
    @Bindable var credentials: GeminiCredentials
    @State private var key = ""
    @State private var confirmsDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gemini APIキー").font(.headline)
            Text("ご自身のAPIキーでGoogleへ直接接続します。キーはこのMacのKeychainに保存します。APIの利用料金はご自身のGoogleプロジェクトに発生します。")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
            Text("モデル：\(GeminiInsightClient.model)").font(.caption)
            Text(credentials.statusText).font(.callout)
            SecureField("Gemini APIキー", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                Button("Keychainへ保存") {
                    credentials.save(key)
                    key = ""
                }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("キーを削除", role: .destructive) { confirmsDeletion = true }.disabled(!credentials.configured)
            }
            if !credentials.message.isEmpty { Text(credentials.message).font(.callout) }
            Text("キーの変更・削除時はAI送信許可を解除します。通常の字幕は継続します。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            Link("Gemini APIの料金を見る", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
                .font(.caption)
        }
        .task { await credentials.refresh() }
        .onDisappear { key = "" }
        .alert("Gemini APIキーを削除しますか？", isPresented: $confirmsDeletion) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { credentials.delete() }
        } message: { Text("このMacに保存したキーを削除し、AI送信許可を解除します。Google側のキーは削除しません。") }
    }
}
