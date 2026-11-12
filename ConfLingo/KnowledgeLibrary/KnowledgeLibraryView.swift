import SwiftUI

struct KnowledgeLibraryView: View {
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    var attachedIDs: Set<UUID> = []
    var choose: ((KnowledgeLibraryEntry) -> Void)?
    @State private var removing: KnowledgeLibraryEntry?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(choose == nil ? "資料ライブラリ" : "ライブラリから追加").font(.title2.bold())
                Spacer()
                if choose == nil { Button("資料を追加", systemImage: "doc.badge.plus") { importing = true } }
                if library.isBusy { ProgressView().controlSize(.small) }
            }
            Text("このMacに保存した資料です。会議で選んだ保存版を使います。閲覧・追加だけでは外部送信しません。")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
            if let error = library.error {
                Text(error).font(.callout).foregroundStyle(DesignTokens.warning).textSelection(.enabled)
            }
            if let selected = library.selected {
                HStack {
                    Button("一覧へ戻る") { library.close() }
                    Spacer()
                    if let choose { Button("この保存版を追加") { choose(selected.entry) }.disabled(attachedIDs.contains(selected.id)) }
                }
                KnowledgeLibraryDetail(saved: selected, fontSize: fontSize)
            } else {
                HStack {
                    TextField("保存名で検索", text: $library.query).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("資料ライブラリの名前検索")
                    Button("再読込") { Task { await library.reload() } }
                }
                if library.entries.isEmpty && !library.isBusy {
                    ContentUnavailableView("保存した資料はありません", systemImage: "books.vertical",
                        description: Text("「資料を追加」から事前登録できます。MeetingやConferenceでも資料を追加・選択できます。"))
                } else if library.filtered.isEmpty && !library.isBusy {
                    Text("一致する保存名はありません。").foregroundStyle(DesignTokens.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(library.filtered) { entry in
                            Surface {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.title).font(.system(size: fontSize, weight: .semibold)).lineLimit(3)
                                    Text("\(entry.kind) · \(entry.count)文書 · \(entry.updatedAt?.formatted() ?? "日時不明")")
                                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                                    if let failure = entry.failure { Text(failure).font(.caption).foregroundStyle(DesignTokens.warning) }
                                    HStack {
                                        Button("内容を見る") { Task { await library.open(entry.id) } }.disabled(entry.failure != nil)
                                        if let choose {
                                            Button(attachedIDs.contains(entry.id) ? "選択済み" : "追加") { choose(entry) }
                                                .disabled(entry.failure != nil || attachedIDs.contains(entry.id))
                                        } else {
                                            Button("削除", role: .destructive) { removing = entry }
                                        }
                                    }
                                    .accessibilityElement(children: .contain)
                                    .accessibilityLabel(entry.title)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .disabled(library.isBusy)
        .task { library.close(); await library.reload() }
        .sheet(isPresented: $importing) { LibraryImportView(library: library, fontSize: fontSize) }
        .alert("保存資料を削除しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("キャンセル", role: .cancel) { removing = nil }
            Button("削除", role: .destructive) {
                if let entry = removing { Task { await library.delete(entry) } }
                removing = nil
            }
        } message: {
            Text("「\(removing?.title ?? "")」のライブラリ内の保存を削除します。使用中の会議、保存済みの引用、元ファイルは残ります。")
        }
    }
}

private struct LibraryImportView: View {
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    @State private var draft = KnowledgeStore()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料を事前に登録").font(.title2.bold())
            Text("ファイルを取り込み、各資料の「ライブラリに保存」を選んでください。閉じると未保存の取り込み内容は破棄されます。")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
            ScrollView {
                KnowledgeMaterialsView(knowledge: draft, library: library, fontSize: fontSize,
                    canEdit: { !draft.isBusy && !library.isBusy }, allowsSelection: false)
            }
            Button("完了") { draft.cancelPendingImports(); dismiss() }.keyboardShortcut(.cancelAction).disabled(library.isBusy)
        }.padding(24).frame(minWidth: 480, idealWidth: 660, minHeight: 480, idealHeight: 650)
            .interactiveDismissDisabled(library.isBusy)
            .onDisappear { draft.cancelPendingImports() }
    }
}

private struct KnowledgeLibraryDetail: View {
    let saved: SavedKnowledge
    let fontSize: Double
    @State private var documentID: UUID?
    private var document: KnowledgeArchive.Document? {
        saved.content.documents.first { $0.document.id == documentID } ?? saved.content.documents.first
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(saved.title).font(.title3.bold()).textSelection(.enabled)
            Text("保存更新 \(saved.updatedAt.formatted()) · 保存版 \(saved.revision.uuidString.prefix(8)) · 読み取り専用")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            if saved.content.isRepository {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(saved.content.documents, id: \.document.id) { item in
                            Button(item.document.displayTitle) { documentID = item.document.id }
                                .font(.callout).buttonStyle(.plain)
                                .foregroundStyle(document?.document.id == item.document.id ? DesignTokens.accent : DesignTokens.text)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 130)
            }
            if let document {
                Text(document.document.displayTitle).font(.headline).textSelection(.enabled)
                Text("元の取り込み \(document.document.importedAt.formatted()) · \(document.document.characterCount)文字")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if let source = document.document.source {
                    Text("作業ツリー \(source.contentHash.prefix(12)) · snapshot \(source.snapshotID)")
                        .font(.caption).textSelection(.enabled)
                }
                ScrollView {
                    Text(document.body).font(.system(size: fontSize)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.id(saved.revision)
    }
}
