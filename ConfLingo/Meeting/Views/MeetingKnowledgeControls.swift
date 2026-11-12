import SwiftUI

struct MeetingKnowledgeControls: View {
    @Bindable var meeting: MeetingWorkspace
    var library: KnowledgeLibrary?
    var fontSize: Double = 16
    @State private var expanded = true

    var body: some View {
        Surface {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    if let library {
                        KnowledgeMaterialsView(knowledge: meeting.knowledge, library: library, fontSize: fontSize,
                            canEdit: { meeting.canEditKnowledge }, importFile: { await meeting.importKnowledge($0) },
                            importRepository: { await meeting.importRepository($0, selected: $1) },
                            attach: { await library.attach($0, to: meeting) })
                    }
                    Picker("音声認識方式", selection: $meeting.recognitionMode) {
                        ForEach(SpeechRecognitionMode.allCases) { Text($0.label).tag($0) }
                    }.disabled(meeting.phase != .idle || meeting.isBusy)
                    Text("資料の用語を優先する場合、開始時に別の認識モデルを準備します。必要に応じてダウンロードします。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    DocumentTermsView(terms: meeting.documentTerms, knowledge: meeting.knowledge,
                        sourceLanguages: [meeting.microphoneLocaleID, meeting.systemLocaleID], targetLanguage: nil,
                        applied: { Task { await meeting.applyDocumentTerms() } })
                    Text(meeting.recognitionStatus).font(.caption).foregroundStyle(DesignTokens.secondary)
                    Toggle("この会議の資料の抜粋を\(meeting.llmSettings.selected.name)へ送信する", isOn: Binding(
                        get: { meeting.knowledge.permitted }, set: { meeting.setKnowledgeAllowed($0) }
                    ))
                    .disabled(!meeting.ai.permitted || meeting.page == .review || meeting.phase == .stopping || meeting.knowledge.isBusy)
                    Text("手動質問に最大5箇所・6,000文字と資料名・位置を送ります。自動提案と終了後要約は別に許可します。資料追加後は許可を確認してください。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                }.padding(.top, 10)
            } label: {
                Label("資料（\(meeting.knowledge.documents.count)）", systemImage: "doc.text.magnifyingglass").font(.headline)
            }
        }
    }
}

struct KnowledgeReferenceView: View {
    let reference: KnowledgeReference
    let fontSize: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(reference.displayTitle).font(.title2.weight(.semibold)).textSelection(.enabled)
            Text("\(reference.provenance) · 取り込み日時 \(reference.importedAt.formatted())")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            Text("取り込んだ時点の抜粋です。原本の変更は反映されません。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            ScrollView {
                Text(reference.snippet).font(.system(size: fontSize)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24).frame(minWidth: 360, idealWidth: 560, maxWidth: 680, minHeight: 280, idealHeight: 420, maxHeight: 600)
    }
}
