import SwiftUI

struct MeetingAISettings: View {
    @Bindable var meeting: MeetingWorkspace
    var openResearch: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if DEBUG
            if meeting.previewUsesLiveAI {
                Text("実API検証：合成発話・音声取得なし・選択したAIへ実通信（API利用料金が発生）")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.warning)
            }
            #endif
            AISendingScopePanel(settings: meeting.llmSettings, answerLanguage: $meeting.answerLanguage,
                permitted: Binding(get: { meeting.ai.permitted }, set: { meeting.setAIAllowed($0) }),
                manualKnowledge: Binding(get: { meeting.knowledge.permitted }, set: { meeting.setKnowledgeAllowed($0) }),
                automatic: Binding(get: { meeting.ai.automaticEnabled }, set: { meeting.setAutomaticAI($0) }),
                automaticKnowledge: Binding(get: { meeting.ai.automaticKnowledgeEnabled }, set: { meeting.setAutomaticKnowledgeAllowed($0) }),
                canEdit: meeting.page != .review && meeting.phase != .stopping,
                canUseKnowledge: !meeting.knowledge.isBusy, canUseAutomatic: !meeting.ai.subscriptionFailed,
                contextDescription: meeting.ai.contextDescription) {
                Text("Web調査：発話・資料の独立した許可と送信内容を、実行前に確認します。")
                    .font(DesignTokens.Typography.body)
                Text(meeting.research.permitted ? "Web調査：許可済み" : "Web調査：オフ").font(DesignTokens.Typography.supporting)
                if let openResearch {
                    Button("Web調査の送信範囲を確認", action: openResearch)
                        .disabled(meeting.page == .review || !meeting.canEditKnowledge)
                }
                Text("終了後要約：振り返りで会議全体の送信計画を確認し、資料を含めるか選択します。手動質問・自動提案の許可は流用しません。")
                    .font(DesignTokens.Typography.body)
            }
            if let usage = meeting.ai.lastUsage {
                Text("直近の使用量：入力 \(usage.inputTokens)・出力 \(usage.outputTokens + usage.thinkingTokens) トークン（思考を含む）")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            }
        }
    }
}
