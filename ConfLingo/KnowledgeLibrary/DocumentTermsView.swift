import SwiftUI

struct DocumentTermsView: View {
    @Bindable var terms: DocumentTerms
    let knowledge: KnowledgeStore
    let sourceLanguages: [String]
    let targetLanguage: String?
    var manual: [KeywordParser.GlossaryEntry] = []
    var applied: () -> Void = {}
    @State private var sourceLanguage = ""
    @State private var message = ""
    @State private var extracting = false
    @State private var newTerm = ""
    @State private var newTarget = ""

    var body: some View {
        DisclosureGroup("資料から専門用語を適用（\(terms.applied.count)語）") {
            VStack(alignment: .leading, spacing: 12) {
                Text("見出し・強調語・コード表記・原語/訳語の表から候補を抽出します。使う語と訳語を確認してください。既存辞書と合わせて100語まで。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Button("資料から用語を抽出") {
                    extracting = true
                    Task {
                        defer { extracting = false }
                        do {
                            terms.extract(try await knowledge.contents())
                            terms.selectCandidates(sourceLanguage: sourceLanguage)
                            message = "候補を選択・編集して適用してください。"
                        }
                        catch { message = "資料を読み込めませんでした。" }
                    }
                }.disabled(extracting || knowledge.isBusy || knowledge.documents.isEmpty)
                Picker("原語の言語", selection: $sourceLanguage) {
                    ForEach(Array(Set(sourceLanguages)).sorted(), id: \.self) { Text(LanguageCatalog.displayName(for: $0)).tag($0) }
                }
                Text(targetLanguage.map { "訳語の言語：\(LanguageCatalog.displayName(for: $0))" } ?? "認識用語のみ")
                    .font(.caption)
                Text("適用・解除は選択中の原語言語だけを変更します。別の言語に適用した用語は保持します。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach($terms.candidates) { $candidate in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Toggle("採用", isOn: $candidate.selected).labelsHidden().accessibilityLabel("\(candidate.term)を選択")
                                    TextField("用語", text: $candidate.term).textFieldStyle(.roundedBorder)
                                    if targetLanguage != nil { TextField("訳語（任意）", text: $candidate.target).textFieldStyle(.roundedBorder) }
                                }
                                Text("\(candidate.documentTitle)\(candidate.line > 0 ? " · \(candidate.line)行" : "") · \(candidate.snippet)")
                                    .font(.caption2).foregroundStyle(DesignTokens.secondary).textSelection(.enabled).lineLimit(3)
                            }
                        }
                    }
                }.frame(maxHeight: terms.candidates.isEmpty ? 0 : 220)
                HStack {
                    TextField("手入力の用語", text: $newTerm).textFieldStyle(.roundedBorder)
                    if targetLanguage != nil { TextField("訳語", text: $newTarget).textFieldStyle(.roundedBorder) }
                    Button("候補に追加") { terms.addManual(term: newTerm, target: newTarget); newTerm = ""; newTarget = "" }
                        .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button("選択した用語を適用") {
                        do {
                            try terms.apply(sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, manual: manual)
                            message = "用語を適用しました。翻訳は以降の処理に反映します。"
                            applied()
                        } catch { message = error.localizedDescription }
                    }.disabled(extracting || knowledge.isBusy || sourceLanguage.isEmpty)
                    Button("この言語の適用を解除") { terms.clear(sourceLanguage: sourceLanguage); applied() }
                }
                if !message.isEmpty { Text(message).font(.caption).textSelection(.enabled) }
            }.padding(.top, 10)
        }
        .onAppear {
            sourceLanguage = sourceLanguages.first ?? ""
            terms.selectCandidates(sourceLanguage: sourceLanguage)
        }
        .onChange(of: sourceLanguages) { sourceLanguage = sourceLanguages.first ?? "" }
        .onChange(of: sourceLanguage) { terms.selectCandidates(sourceLanguage: sourceLanguage) }
    }
}
