import SwiftUI

struct KnowledgeLibraryView: View {
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    var attachedIDs: Set<UUID> = []
    var choose: ((KnowledgeLibraryEntry) -> Void)?
    @State private var removing: KnowledgeLibraryEntry?
    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PageHeading(title: choose == nil ? "資料ライブラリ" : "ライブラリから追加",
                            subtitle: "このMacに保存した資料。閲覧・追加だけでは外部送信しません。", eyebrow: "ConfLingo")
                Spacer()
                if choose == nil { Button("資料を追加", systemImage: "doc.badge.plus") { importing = true } }
                if library.isBusy { ProgressView().controlSize(.small) }
            }
            if let failure = library.failure { InlineMessage(failure) }
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
                    Button("再読込", systemImage: "arrow.clockwise") { Task { await library.reload() } }
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
                            LibraryEntryRow(title: entry.title, symbol: "books.vertical",
                                            subtitle: "\(entry.kind) · \(entry.count)文書",
                                            detail: entry.updatedAt.map { "保存更新 \($0.formatted(date: .abbreviated, time: .shortened))" },
                                            failure: entry.failure, open: { Task { await library.open(entry.id) } }) {
                                if let choose {
                                    Button(attachedIDs.contains(entry.id) ? "選択済み" : "追加") { choose(entry) }
                                        .disabled(entry.failure != nil || attachedIDs.contains(entry.id))
                                        .accessibilityLabel(attachedIDs.contains(entry.id) ? "\(entry.title)、選択済み" : "\(entry.title)を追加")
                                } else {
                                    Button("削除", systemImage: "trash", role: .destructive) { removing = entry }
                                        .buttonStyle(AppButtonStyle(.destructive)).accessibilityLabel("\(entry.title)を削除")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
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
            SheetHeader(title: "資料を事前に登録") { draft.cancelPendingImports(); dismiss() }.disabled(library.isBusy)
            Text("ファイルを取り込み、各資料の「ライブラリに保存」を選んでください。閉じると未保存の取り込み内容は破棄されます。")
                .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary)
            ScrollView {
                KnowledgeMaterialsView(knowledge: draft, library: library, fontSize: fontSize,
                    canEdit: { !draft.isBusy && !library.isBusy }, allowsSelection: false)
            }
        }.sheetSurface().frame(minWidth: 480, idealWidth: 660, minHeight: 480, idealHeight: 650)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(saved.title).font(DesignTokens.Typography.heading).textSelection(.enabled)
            Text("保存更新 \(saved.updatedAt.formatted()) · 読み取り専用")
                .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            if saved.content.isRepository {
                ScrollView {
                    LazyVStack(alignment: .leading) {
                        ForEach(saved.content.documents, id: \.document.id) { item in
                            Button(item.document.displayTitle) { documentID = item.document.id }
                                .font(DesignTokens.Typography.body).buttonStyle(.plain)
                                .lineLimit(1).truncationMode(.middle)
                                .help(item.document.displayTitle)
                                .foregroundStyle(document?.document.id == item.document.id ? DesignTokens.accent : DesignTokens.text)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 36, maxHeight: 130)
            }
            if let document {
                Text(document.document.displayTitle).font(DesignTokens.Typography.heading).textSelection(.enabled)
                Text("元の取り込み \(document.document.importedAt.formatted()) · \(document.document.characterCount)文字")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                DisclosureGroup("技術情報") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("保存版 \(saved.revision.uuidString)")
                            if let source = document.document.source {
                                Text("ハッシュ \(source.contentHash)")
                                Text("snapshot \(source.snapshotID)")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .font(DesignTokens.Typography.supporting).textSelection(.enabled)
                    }.frame(maxHeight: 100)
                }.font(DesignTokens.Typography.supporting)
                KnowledgeBodyView(text: document.body, fontSize: fontSize)
                    .frame(minHeight: fontSize * 1.5 + 8)
                    .layoutPriority(1)
                    .id(document.document.id)
            }
        }.id(saved.revision)
    }
}
