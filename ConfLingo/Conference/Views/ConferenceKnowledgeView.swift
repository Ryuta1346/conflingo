import SwiftUI

struct ConferenceKnowledgeView: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    let sourceLanguage: String
    let targetLanguage: String?
    var manualGlossary: [KeywordParser.GlossaryEntry] = []
    let applyTerms: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: "Conferenceの資料・用語") { dismiss() }
            ScrollView {
                ConferenceMaterialsContents(workspace: workspace, library: library, fontSize: fontSize,
                    sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                    manualGlossary: manualGlossary, applyTerms: applyTerms)
            }
        }.sheetSurface().frame(minWidth: 480, idealWidth: 680, minHeight: 480, idealHeight: 700)
    }
}

struct ConferenceMaterialsContents: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    let sourceLanguage: String
    let targetLanguage: String?
    var manualGlossary: [KeywordParser.GlossaryEntry] = []
    var showsRecognitionMode = false
    let applyTerms: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            KnowledgeMaterialsView(knowledge: workspace.knowledge, library: library, fontSize: fontSize,
                canEdit: { workspace.canEditKnowledge })
            if showsRecognitionMode {
                Picker("音声認識方式", selection: $workspace.recognitionMode) {
                    ForEach(SpeechRecognitionMode.allCases) { Text($0.label).tag($0) }
                }.disabled(workspace.store.phase != .idle)
                Text("資料の用語を優先する場合、選択時に別の認識モデルを準備します。必要に応じてダウンロードします。")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            }
            DocumentTermsView(terms: workspace.terms, knowledge: workspace.knowledge,
                sourceLanguages: [sourceLanguage], targetLanguage: targetLanguage, manual: manualGlossary, applied: applyTerms)
            Text(workspace.recognitionStatus).font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
        }.padding(1)
    }
}
