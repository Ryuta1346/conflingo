import SwiftUI

struct AISendingScopePanel<Additional: View>: View {
    let settings: LLMSettings
    @Binding var answerLanguage: AnswerLanguage
    @Binding var permitted: Bool
    @Binding var manualKnowledge: Bool
    @Binding var automatic: Bool
    @Binding var automaticKnowledge: Bool
    var canEdit = true
    var canUseKnowledge = true
    var canUseAutomatic = true
    let contextDescription: String
    @ViewBuilder var additional: Additional
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(settings.selected.destinationLabel).font(DesignTokens.Typography.heading)
                Spacer()
                Button("LLM設定") { openSettings() }
            }
            Picker("AIの回答言語", selection: $answerLanguage) {
                ForEach(AnswerLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Text("変更は次の回答から反映されます。音声は送りません。")
                .font(DesignTokens.Typography.body)
            Text("送信先：\(settings.selected.baseURL)。料金・データ保持・学習への利用は、接続先サービスとご自身の契約・実行環境の条件をご確認ください。")
                .font(DesignTokens.Typography.body).textSelection(.enabled)
            VStack(alignment: .leading, spacing: 12) {
                Toggle("発話を使ったAI支援を許可", isOn: $permitted)
                Text("手動質問では、許可前を含む直近の確定発話を最大30件送ります。質問ボタンを押したときだけ送信します。")
                    .font(DesignTokens.Typography.body)
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("手動質問にも資料を使う", isOn: $manualKnowledge)
                        .disabled(!permitted || !canUseKnowledge)
                    Text("手動質問に最大5箇所・6,000文字と資料名・位置を送ります。資料追加後は許可を確認してください。")
                        .font(DesignTokens.Typography.body)
                    Toggle("自動提案を使う（追加のAI処理が発生）", isOn: $automatic)
                        .disabled(!permitted || !canUseAutomatic)
                    Text("許可後の確定発話をきっかけに、関連する会話を送ります。既存の提案回数上限を適用します。")
                        .font(DesignTokens.Typography.body)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("自動提案にも資料を使う", isOn: $automaticKnowledge)
                            .disabled(!permitted || !automatic || !canUseKnowledge)
                        Text("自動提案に最大5箇所・6,000文字と資料名・位置を追加します。手動質問・終了後要約の資料許可とは別の設定です。")
                            .font(DesignTokens.Typography.body)
                        if !automatic { Text("自動提案を許可すると変更できます。").font(DesignTokens.Typography.supporting) }
                    }.padding(.leading, 16)
                    if !permitted { Text("発話を使ったAI支援を許可すると変更できます。").font(DesignTokens.Typography.supporting) }
                    if !canUseKnowledge { Text("資料の処理が完了するまでお待ちください。").font(DesignTokens.Typography.supporting) }
                }.padding(.leading, 16)
            }.disabled(!canEdit)
            Text(contextDescription).font(DesignTokens.Typography.body)
            Divider()
            additional
        }.foregroundStyle(DesignTokens.text)
    }
}
