import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeMaterialsView: View {
    @Bindable var knowledge: KnowledgeStore
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    let canEdit: () -> Bool
    var allowsSelection = true
    var importFile: ((URL) async -> Void)?
    var importRepository: ((RepositoryScan, Set<String>) async -> Void)?
    var attach: ((UUID) async -> Bool)?
    @State private var importing = false
    @State private var selecting = false
    @State private var saving: KnowledgeDocument?
    @State private var removing: KnowledgeDocument?
    @State private var reading: KnowledgeArchive.Document?
    @State private var query = ""
    @State private var selectedReference: KnowledgeReference?
    @State private var notice: UserMessage?
    @State private var importResults: [UserMessage] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { addButtons }
                VStack(alignment: .leading) { addButtons }
            }
            RepositoryKnowledgeControls(knowledge: knowledge, canEdit: canEdit) { scan, paths in
                importResults = []; notice = nil
                if let importRepository { await importRepository(scan, paths) }
                else { await knowledge.importRepository(scan, selected: paths) }
            }
            Text("UTF-8の.md / .txt、またはリポジトリ。直接追加した資料はこのセッション内に保持します。「ライブラリに保存」で次回も使えます。")
                .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            if knowledge.documents.isEmpty { Text("資料なし。実行中も追加できます。").foregroundStyle(DesignTokens.secondary) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(knowledge.documents) { document in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(document.displayTitle).font(DesignTokens.Typography.body.weight(.medium)).lineLimit(2)
                            HStack {
                                Button("本文") { Task { await read(document) } }.disabled(knowledge.isBusy)
                                if document.source == nil || document.id == knowledge.documents.first(where: { $0.source != nil })?.id {
                                    Button(document.source == nil ? "ライブラリに保存" : "リポジトリを保存") { saving = document }
                                        .disabled(!canEdit() || library.isBusy)
                                }
                                Button("取り外す", role: .destructive) { removing = document }
                                    .disabled(!canEdit())
                                    .accessibilityLabel("\(document.displayTitle)を取り外す")
                            }.font(DesignTokens.Typography.supporting)
                            if let entry = knowledge.librarySources[document.id] {
                                Text("保存版：\(entry.title)").font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                            }
                        }
                    }
                }
            }.frame(maxHeight: knowledge.documents.isEmpty ? 0 : 180)
            if knowledge.isBusy { ProgressView("資料を処理しています…") }
            if importResults.isEmpty, let notice = knowledge.notice { InlineMessage(notice) }
            if let notice { InlineMessage(notice) }
            ForEach(Array(importResults.enumerated()), id: \.offset) { _, result in InlineMessage(result) }
            HStack {
                TextField("資料をこのMacで検索", text: $query).textFieldStyle(.roundedBorder)
                    .onSubmit { search() }.accessibilityLabel("資料検索")
                Button("検索", action: search).disabled(knowledge.isBusy || knowledge.documents.isEmpty)
            }
            if knowledge.searchState == .empty { InlineMessage(.information, "一致する資料はありません。") }
            if knowledge.searchState == .failed { InlineMessage(.failure, "検索できませんでした。再試行してください。") }
            ForEach(knowledge.results) { reference in
                Button { selectedReference = reference } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reference.displayTitle) · \(reference.provenance)").font(DesignTokens.Typography.supporting.bold())
                        Text(reference.snippet).font(DesignTokens.Typography.supporting).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(AppButtonStyle(.link))
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .text], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                let generation = knowledge.importGeneration
                Task {
                    var results: [UserMessage] = []
                    notice = nil
                    importResults = []
                    for url in urls {
                        guard generation == knowledge.importGeneration, canEdit() else { break }
                        if let importFile { await importFile(url) } else { await knowledge.add(url: url); knowledge.setPermission(false) }
                        if let result = knowledge.notice {
                            results.append(UserMessage(result.kind, "\(url.lastPathComponent)：\(result.text)", details: result.details))
                        }
                    }
                    if generation == knowledge.importGeneration { importResults = results }
                }
            case .failure(let error): notice = UserMessage(.failure, "資料を選択できませんでした。", details: error.localizedDescription)
            }
        }
        .sheet(isPresented: $selecting) {
            VStack {
                SheetHeader(title: "保存資料を選択") { selecting = false }
                KnowledgeLibraryView(library: library, fontSize: fontSize, attachedIDs: Set(knowledge.librarySources.values.map(\.id))) { entry in
                    Task {
                        guard canEdit() else { return }
                        let success: Bool
                        if let attach { success = await attach(entry.id) }
                        else { success = await library.attach(entry.id, to: knowledge) }
                        if success { selecting = false; library.close() }
                    }
                }
            }.sheetSurface().frame(minWidth: 480, idealWidth: 640, minHeight: 400)
        }
        .sheet(item: $saving) { document in
            MaterialSaveView(knowledge: knowledge, library: library, document: document)
        }
        .sheet(item: $reading) { item in
            MaterialBodyView(item: item, fontSize: fontSize)
        }
        .sheet(item: $selectedReference) { KnowledgeReferenceView(reference: $0, fontSize: fontSize) }
        .alert("資料を取り外しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("キャンセル", role: .cancel) { removing = nil }
            Button("取り外す", role: .destructive) {
                if let removing, canEdit() {
                    importResults = []; notice = nil
                    Task {
                    if removing.source == nil { await knowledge.remove(removing.id) } else { await knowledge.removeRepository() }
                    }
                }
                removing = nil
            }
        } message: { Text("以降の検索から除外します。既存の引用、保存資料、元ファイルは残ります。リポジトリは一括で取り外します。") }
        .onChange(of: knowledge.importGeneration) { selecting = false; importing = false; saving = nil; importResults = []; notice = nil }
    }

    private var addButtons: some View {
        Group {
            Button("資料を追加", systemImage: "doc.badge.plus") { importing = true }.disabled(!canEdit())
            if allowsSelection {
                Button("ライブラリから選択", systemImage: "books.vertical") { selecting = true }.disabled(!canEdit() || library.isBusy)
            }
        }
    }
    private func search() { notice = nil; importResults = []; Task { await knowledge.search(query) } }
    private func read(_ document: KnowledgeDocument) async {
        notice = nil
        do { reading = try await knowledge.contents().first { $0.document.id == document.id } }
        catch { notice = UserMessage(.failure, "本文を開けませんでした。再試行してください。", details: error.localizedDescription) }
    }
}

extension KnowledgeArchive.Document: Identifiable { var id: UUID { document.id } }

private struct MaterialBodyView: View {
    let item: KnowledgeArchive.Document
    let fontSize: Double
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(title: item.document.displayTitle) { dismiss() }
            ScrollView { Text(item.body).font(.system(size: fontSize)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }.sheetSurface().frame(minWidth: 420, idealWidth: 620, minHeight: 360)
    }
}

private struct MaterialSaveView: View {
    @Bindable var knowledge: KnowledgeStore
    @Bindable var library: KnowledgeLibrary
    let document: KnowledgeDocument
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var replacementID: UUID?
    private var targets: [KnowledgeLibraryEntry] {
        library.entries.filter { $0.failure == nil && $0.kind == (document.source == nil ? "文書" : "リポジトリ") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料をライブラリに保存").font(DesignTokens.Typography.title)
            Text("本文をこのMacに保持します。セッションを破棄しても残ります。")
            TextField("保存名", text: $title).textFieldStyle(.roundedBorder)
            Picker("更新先", selection: $replacementID) {
                Text("この資料の保存先（初回は新規）").tag(nil as UUID?)
                ForEach(targets) { Text($0.title).tag(Optional($0.id)) }
            }
            if replacementID != nil { Text("選んだ保存資料を置き換えます。使用中のコピーは変更しません。").font(DesignTokens.Typography.supporting) }
            if let failure = library.failure { InlineMessage(failure) }
            HStack {
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { Task {
                    if await library.save(from: knowledge, documentID: document.source == nil ? document.id : nil,
                                          title: title, replacing: targets.first { $0.id == replacementID }) { dismiss() }
                } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 200)
                    .buttonStyle(AppButtonStyle(.primary))
            }
        }.sheetSurface().frame(minWidth: 440).disabled(library.isBusy || knowledge.isBusy)
            .interactiveDismissDisabled(library.isBusy)
            .task { title = knowledge.librarySources[document.id]?.title ?? document.source?.name ?? document.title; await library.reload() }
    }
}
