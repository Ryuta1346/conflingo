import SwiftUI

struct ConferenceAssistanceView: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    @State private var question = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資料と発話から支援").font(.headline)
            Text("確定した発話（最大30件）と質問を\(workspace.settings.selected.name)へ送ります。資料の参照も許可した場合、関連する抜粋を最大5箇所送ります。音声は送りません。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("発話を使ったAI支援を許可", isOn: Binding(get: { workspace.assistance.permitted },
                set: { workspace.setAssistancePermission($0) }))
            Toggle("手動質問にも資料を使う", isOn: Binding(get: { workspace.knowledge.permitted },
                set: { workspace.knowledge.setPermission($0) })).disabled(!workspace.assistance.permitted)
            Toggle("自動提案を使う", isOn: Binding(get: { workspace.assistance.automaticEnabled },
                set: { workspace.assistance.setAutomatic($0, after: workspace.assistanceStore.finals.last?.startOffset ?? 0) }))
                .disabled(!workspace.assistance.permitted)
            Toggle("自動提案にも資料を使う", isOn: Binding(get: { workspace.assistance.automaticKnowledgeEnabled },
                set: { workspace.assistance.setAutomaticKnowledge($0) })).disabled(!workspace.assistance.automaticEnabled)
            TextField("発話や資料について質問する", text: $question, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("質問する") { Task { await workspace.askAssistance(question) } }
                .disabled(!workspace.canAskAssistance || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 2_000)
            Text(workspace.assistance.statusText).font(.caption)
            ForEach(workspace.assistance.insights.reversed()) { answer in
                AssistanceAnswerView(answer: answer, events: workspace.assistanceStore.finals, research: { workspace.research.open($0, evidenceIDs: answer.evidenceIDs) })
            }
            DisclosureGroup("発話からWebで調べる") {
                ForEach(workspace.assistanceStore.finals.suffix(30)) { event in
                    HStack {
                        Text(event.text).lineLimit(2)
                        Button("Webで調べる") { workspace.research.open(event.text, evidenceIDs: [event.id]) }
                    }
                }
            }
            WebResearchControls(research: workspace.research, language: workspace.answerLanguage,
                enabled: workspace.canEditKnowledge)
        }
        .disabled(workspace.store.phase == .preparing || workspace.store.phase == .stopping)
    }
}
