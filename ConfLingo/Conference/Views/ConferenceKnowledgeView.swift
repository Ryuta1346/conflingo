import SwiftUI

struct ConferenceKnowledgeView: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    @Bindable var library: KnowledgeLibrary
    let sessions: SessionsLibrary
    let fontSize: Double
    let stopAudio: () -> Void
    let sourceLanguage: String
    let targetLanguage: String?
    var manualGlossary: [KeywordParser.GlossaryEntry] = []
    let applyTerms: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var reference: KnowledgeReference?
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Conferenceの資料").font(.title2.bold())
                Spacer()
                if workspace.store.phase == .listening { Button("音声を停止", action: stopAudio) }
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SessionSaveControls(library: sessions, snapshot: snapshot) {
                        guard let snapshot else { return }
                        Task { await sessions.save(snapshot) }
                    }
                    ConferenceExportButton(store: workspace.store, sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage, support: workspace.snapshot)
                    KnowledgeMaterialsView(knowledge: workspace.knowledge, library: library, fontSize: fontSize,
                        canEdit: { workspace.canEditKnowledge })
                    Divider()
                    Picker("音声認識方式", selection: $workspace.recognitionMode) {
                        ForEach(SpeechRecognitionMode.allCases) { Text($0.label).tag($0) }
                    }.disabled(workspace.store.phase != .idle)
                    Text("資料の用語を優先する場合、選択時に別の認識モデルを準備します。必要に応じてダウンロードします。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    DocumentTermsView(terms: workspace.terms, knowledge: workspace.knowledge,
                        sourceLanguages: [sourceLanguage], targetLanguage: targetLanguage, manual: manualGlossary, applied: applyTerms)
                    Text(workspace.recognitionStatus).font(.caption).foregroundStyle(DesignTokens.secondary)
                    Divider()
                    HStack {
                        Text("資料に質問").font(.headline)
                        Spacer()
                        Button("LLM設定") { showSettings = true }
                    }
                    Text("質問と関連する資料の抜粋（最大5箇所・6,000文字）を\(workspace.settings.selected.name)へ送ります。字幕・音声は送りません。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    Toggle("資料への質問を許可", isOn: Binding(get: { workspace.questionPermitted }, set: { workspace.setQuestionPermission($0) }))
                    Picker("回答言語", selection: $workspace.answerLanguage) {
                        ForEach(AnswerLanguage.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.onChange(of: workspace.answerLanguage) { workspace.cancel() }
                    TextField("資料について聞きたいこと", text: $question, axis: .vertical).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("質問する") { Task { await workspace.ask(question) } }.buttonStyle(.borderedProminent)
                            .disabled(!workspace.canAsk || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if workspace.isGenerating { ProgressView().controlSize(.small); Button("AIを中断") { workspace.cancel() } }
                    }
                    if !workspace.message.isEmpty { Text(workspace.message).font(.callout).foregroundStyle(DesignTokens.warning) }
                    if !workspace.preview.isEmpty { Text(workspace.preview).font(.system(size: fontSize)).textSelection(.enabled) }
                    ForEach(workspace.answers.reversed()) { answer in
                        Surface {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(answer.text).font(.system(size: fontSize)).textSelection(.enabled)
                                if answer.knowledgeReferences.isEmpty { Text("資料根拠なし・要確認").font(.caption) }
                                ForEach(answer.knowledgeReferences) { item in
                                    Button("\(item.displayTitle) · \(item.provenance)") { reference = item }.font(.caption)
                                }
                            }
                        }
                    }
                    Divider()
                    ConferenceCorrectionView(workspace: workspace, sourceLanguage: sourceLanguage,
                        targetLanguage: targetLanguage, fontSize: fontSize)
                }.padding(.trailing, 8)
            }
        }.padding(24).frame(minWidth: 480, idealWidth: 720, minHeight: 480, idealHeight: 700)
            .sheet(item: $reference) { KnowledgeReferenceView(reference: $0, fontSize: fontSize) }
            .sheet(isPresented: $showSettings) {
                VStack {
                    LLMSettingsView(settings: workspace.settings)
                    Button("閉じる") { showSettings = false }.keyboardShortcut(.cancelAction)
                }.padding().frame(minWidth: 560, minHeight: 420)
            }
    }

    private var snapshot: SessionSnapshot? {
        workspace.store.sessionSnapshot(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, support: workspace.snapshot)
    }
}
