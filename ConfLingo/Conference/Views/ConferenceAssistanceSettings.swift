import SwiftUI

struct ConferenceAssistanceSettings: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    var openResearch: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "AI設定・送信範囲") { dismiss() }
            ScrollView {
                AISendingScopePanel(settings: workspace.settings, answerLanguage: $workspace.answerLanguage,
                    permitted: Binding(get: { workspace.assistance.permitted }, set: { workspace.setAssistancePermission($0) }),
                    manualKnowledge: Binding(get: { workspace.knowledge.permitted }, set: { workspace.knowledge.setPermission($0) }),
                    automatic: Binding(get: { workspace.assistance.automaticEnabled }, set: {
                        workspace.assistance.setAutomatic($0, after: workspace.assistanceStore.finals.last?.startOffset ?? 0)
                    }),
                    automaticKnowledge: Binding(get: { workspace.assistance.automaticKnowledgeEnabled }, set: { workspace.assistance.setAutomaticKnowledge($0) }),
                    canEdit: workspace.canEditKnowledge, canUseKnowledge: !workspace.knowledge.isBusy,
                    canUseAutomatic: !workspace.assistance.subscriptionFailed,
                    contextDescription: workspace.assistance.contextDescription) {
                    Toggle("資料だけの質問を許可", isOn: Binding(get: { workspace.questionPermitted }, set: { workspace.setQuestionPermission($0) }))
                        .disabled(!workspace.canEditKnowledge)
                    Text("資料のみ：質問と関連する資料の抜粋（最大5箇所・6,000文字）を質問ボタンで送ります。字幕・音声は送りません。発話を使ったAI支援とは独立した許可です。")
                        .font(DesignTokens.Typography.body)
                    Text("Web調査：発話・資料の独立した許可と送信内容を、実行前に確認します。")
                        .font(DesignTokens.Typography.body)
                    Text(workspace.research.permitted ? "Web調査：許可済み" : "Web調査：オフ").font(DesignTokens.Typography.supporting)
                    if let openResearch {
                        Button("Web調査の送信範囲を確認", action: openResearch).disabled(!workspace.canEditKnowledge)
                    }
                    Text("字幕補正：確定字幕の「資料で補正」から、選択した発話・訳文・関連資料・用語を確認し、独立して許可します。")
                        .font(DesignTokens.Typography.body)
                }.padding(1)
                .disabled(workspace.store.phase == .preparing || workspace.store.phase == .stopping)
            }
        }.sheetSurface().frame(minWidth: 480, idealWidth: 600, minHeight: 480, idealHeight: 640)
    }
}
