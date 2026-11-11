import SwiftUI
import UniformTypeIdentifiers

struct MeetingKnowledgeControls: View {
    @Bindable var meeting: MeetingWorkspace
    var library: KnowledgeLibrary?
    var fontSize: Double
    @State private var query = ""
    @State private var showsImporter = false
    @State private var importError = ""
    @State private var removing: KnowledgeDocument?
    @State private var expanded: Bool

    init(meeting: MeetingWorkspace, library: KnowledgeLibrary? = nil, fontSize: Double = 16) {
        self.fontSize = fontSize
        self.library = library
        self.meeting = meeting
        _expanded = State(initialValue: meeting.page == .setup)
    }

    private var knowledge: KnowledgeStore { meeting.knowledge }

    var body: some View {
        Surface {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("会議内の資料は、会議破棄・アプリ終了で消えます。「ライブラリに保存」した本文は残り、次の会議で選べます。元ファイルは変更しません。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    if meeting.page == .setup {
                        Button("資料を追加", systemImage: "doc.badge.plus") { showsImporter = true }
                            .disabled(meeting.isBusy || knowledge.isBusy || meeting.phase != .idle)
                        Text("UTF-8の.md / .txt · 20文書まで · 1文書1 MiB・10万文字、合計50万文字")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                    }
                    RepositoryKnowledgeControls(meeting: meeting)
                    if meeting.page == .setup, let library {
                        MeetingLibraryControls(meeting: meeting, library: library, fontSize: fontSize)
                    }
                    if knowledge.documents.isEmpty {
                        Text("資料なし。準備画面から追加できます。")
                            .font(.callout).foregroundStyle(DesignTokens.secondary)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(knowledge.documents) { document in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(document.displayTitle).lineLimit(2)
                                Text("\(document.characterCount)文字").font(.caption).foregroundStyle(DesignTokens.secondary)
                            }
                            Spacer()
                            Button("取り外す", role: .destructive) { removing = document }
                                .disabled(knowledge.isBusy)
                                .accessibilityLabel("\(document.title)を取り外す")
                        }
                    }
                        }
                    }.frame(maxHeight: knowledge.documents.isEmpty ? 0 : 220)
                    if knowledge.isBusy { ProgressView().controlSize(.small) }
                    if !knowledge.message.isEmpty { Text(knowledge.message).font(.caption) }
                    if !importError.isEmpty { Text(importError).font(.caption).foregroundStyle(DesignTokens.warning) }
                    HStack {
                        TextField("資料をこのMacで検索", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { search() }
                            .accessibilityLabel("資料検索")
                        Button("検索", action: search).disabled(knowledge.isBusy || knowledge.documents.isEmpty)
                    }
                    Text("日英の単語で検索します。部分文字列では一致しない場合があります。検索だけでは外部送信しません。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    searchResults
                    Toggle("この会議の資料の抜粋をGeminiへ送信する", isOn: Binding(
                        get: { knowledge.permitted }, set: { meeting.setKnowledgeAllowed($0) }
                    ))
                    .disabled(!meeting.ai.permitted || meeting.page == .review || meeting.phase == .stopping || knowledge.isBusy)
                    Text("この許可は手動質問用です。最大5箇所・6,000文字と資料名・位置を送ります。自動提案ではAI設定の「自動提案にも資料を使う」を選択します。終了後要約の資料参照は、要約の確認画面で選択します。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    Text(knowledge.permitted && meeting.ai.permitted ? "手動質問の資料送信を許可済み" : "手動質問の資料送信オフ・検索と閲覧はこのMac内")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                }.padding(.top, 10)
            } label: {
                Label("資料（\(knowledge.documents.count)）", systemImage: "doc.text.magnifyingglass").font(.headline)
            }
        }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.plainText, UTType(filenameExtension: "md") ?? .text]) { result in
            switch result {
            case .success(let url):
                importError = ""
                Task { await meeting.importKnowledge(url) }
            case .failure: importError = "資料を選択できませんでした。もう一度操作してください。"
            }
        }
        .alert("資料を取り外しますか？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("キャンセル", role: .cancel) { removing = nil }
            Button("取り外す", role: .destructive) {
                if let document = removing { Task { await knowledge.remove(document.id) } }
                removing = nil
            }
        } message: {
            Text("今後の検索・送信から除外します。既存の回答と書き出したMarkdownの引用は残ります。元ファイルは削除しません。")
        }
    }

    @ViewBuilder private var searchResults: some View {
        switch knowledge.searchState {
        case .idle: EmptyView()
        case .searching: ProgressView("資料を検索しています…")
        case .empty: Text("一致する資料はありません。別の単語で検索してください。").font(.caption)
        case .failed: Text("資料を検索できませんでした。もう一度検索してください。").font(.caption)
        case .found:
            ForEach(knowledge.results) { reference in
                Button { meeting.selectedKnowledge = reference } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reference.displayTitle) · \(reference.provenance)").font(.caption.weight(.semibold))
                        Text(reference.snippet).font(.caption).lineLimit(3)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                    .accessibilityLabel("\(reference.displayTitle)の\(reference.provenance)を開く")
            }
        }
    }

    private func search() { Task { await knowledge.search(query) } }
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
