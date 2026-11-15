import SwiftUI

struct ConferenceCorrectionView: View {
    @Bindable var workspace: ConferenceKnowledgeWorkspace
    let sourceLanguage: String
    let targetLanguage: String?
    let fontSize: Double
    @State private var unitID: UUID?
    @State private var reference: KnowledgeReference?

    private var unit: TranslationUnit? { workspace.store.units.first { $0.id == unitID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("資料で原文・訳文を補正").font(DesignTokens.Typography.heading)
            Text("選んだ確定発話、通常訳、関連資料の抜粋、適用用語を\(workspace.settings.selected.name)へ送ります。原文を残し、採用した候補だけを保存・出力します。音声は送りません。")
                .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)
            Toggle("字幕と資料を使う補正を許可", isOn: Binding(get: { workspace.correctionPermitted }, set: { workspace.setCorrectionPermission($0) }))
            Picker("補正する発話", selection: $unitID) {
                Text("発話を選択").tag(nil as UUID?)
                ForEach(workspace.store.units) { item in
                    Text("\(item.startTime.map(MarkdownExporter.timestamp) ?? "") · \(String(item.english.prefix(70)))").tag(Optional(item.id))
                }
            }
            if let unit {
                Text(unit.english).font(.system(size: fontSize)).textSelection(.enabled)
                if let translation = unit.japanese { Text(translation).font(.system(size: fontSize)).textSelection(.enabled) }
                DisclosureGroup("参照する資料を確認") { CorrectionReferencePreview(knowledge: workspace.knowledge, text: unit.english) }
                Button("資料で補正する") { Task {
                    await workspace.correct(unitID: unit.id, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
                } }.disabled(!workspace.correctionPermitted || !workspace.canEditKnowledge || workspace.isGenerating)
            }
            ForEach(workspace.corrections.reversed()) { correction in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(correction.adopted ? "採用した補正" : "補正候補 · 要確認").font(DesignTokens.Typography.heading)
                        Text("元の原文").font(DesignTokens.Typography.supporting)
                        Text(correction.original.sourceText).textSelection(.enabled)
                        Text("補正後の原文").font(DesignTokens.Typography.supporting)
                        Text(correction.sourceText).font(.system(size: fontSize)).textSelection(.enabled)
                        if let original = correction.original.translation { Text("元の訳文：\(original)").textSelection(.enabled) }
                        if let translation = correction.translation { Text(translation).font(.system(size: fontSize)).textSelection(.enabled) }
                        ForEach(correction.references) { item in
                            Button("\(item.displayTitle) · \(item.provenance)") { reference = item }.buttonStyle(AppButtonStyle(.link))
                        }
                        Button(correction.adopted ? "採用を解除して元に戻す" : "この補正を採用") {
                            workspace.adoptCorrection(correction.id, adopted: !correction.adopted)
                        }
                    }
                }
            }
        }.sheet(item: $reference) { KnowledgeReferenceView(reference: $0, fontSize: fontSize) }
    }
}

private struct CorrectionReferencePreview: View {
    let knowledge: KnowledgeStore
    let text: String
    @State private var references: [KnowledgeReference] = []
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if references.isEmpty {
                if message.isEmpty { InlineMessage(.information, "関連資料なし") }
                else { InlineMessage(.failure, message) }
            }
            ForEach(references) { reference in
                Text("\(reference.displayTitle) · \(reference.provenance)").font(DesignTokens.Typography.supporting.bold())
                Text(reference.snippet).font(DesignTokens.Typography.supporting).textSelection(.enabled)
            }
        }.task(id: text + knowledge.revision.uuidString) {
            do { message = ""; references = try await knowledge.localReferences(text) }
            catch { references = []; message = "資料を検索できませんでした。" }
        }
    }
}
