import SwiftUI

struct SessionsView: View {
    @Bindable var library: SessionsLibrary
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = library.error { SessionErrorBanner(message: error).padding(16) }
            if library.isBusy { ProgressView().padding(12).accessibilityLabel("保存したセッションを処理中") }
            if let selected = library.selected {
                SavedSessionView(saved: selected, fontSize: fontSize, back: library.closeDetail) {
                    if let entry = library.entries.first(where: { $0.id == selected.id }) { library.requestDelete(entry) }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        PageHeading(title: "保存したセッション", subtitle: "このMacに保存した会議と字幕。", eyebrow: "ライブラリ")
                        HStack {
                            TextField("セッション名で検索", text: $library.query)
                                .textFieldStyle(.roundedBorder).accessibilityLabel("セッション名で検索")
                            Button("再読込", systemImage: "arrow.clockwise") { Task { await library.reload() } }
                        }
                        Text("自動保存はオフです。削除しても、書き出したMarkdownと元資料は残ります。")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                        if library.filtered.isEmpty {
                            ContentUnavailableView(library.query.isEmpty ? "保存したセッションはありません" : "一致するセッションはありません",
                                systemImage: "folder", description: Text(library.query.isEmpty ? "会議の終了後、または字幕の停止後に「このMacに保存」を選んでください。" : "別の名前で検索してください。"))
                        }
                        LazyVStack(spacing: 12) {
                            ForEach(library.filtered) { entry in
                                SavedSessionRow(entry: entry, open: { Task { await library.open(entry.id) } },
                                                delete: { library.requestDelete(entry) })
                            }
                        }
                    }
                    .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
                }
            }
        }
        .disabled(library.isBusy)
        .alert("保存したセッションを削除しますか？", isPresented: Binding(
            get: { library.pendingDelete != nil }, set: { if !$0 { library.cancelDelete() } }
        ), presenting: library.pendingDelete) { entry in
            Button("キャンセル", role: .cancel, action: library.cancelDelete)
            Button("削除する", role: .destructive) { Task { await library.confirmDelete(entry) } }
        } message: { entry in
            Text("「\(entry.title)」のアプリ内保存を削除します。元資料・書き出したMarkdown・現在の会議は削除しません。")
        }
    }
}

struct SavedSessionRow: View {
    let entry: SessionListEntry
    let open: () -> Void
    var delete: (() -> Void)?

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.kind == "Meeting" ? "person.2" : "captions.bubble")
                        .foregroundStyle(DesignTokens.accent).font(.title2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title).font(.headline).textSelection(.enabled)
                        Text("\(entry.kind) · 開始 \(entry.startedAt.map { MarkdownExporter.dateFormatter.string(from: $0) } ?? "未取得")")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                        if let date = entry.updatedAt {
                            Text("保存更新 \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(DesignTokens.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let failure = entry.failure { Text(failure).font(.callout).foregroundStyle(DesignTokens.warning) }
                HStack {
                    Button("開く", systemImage: "arrow.right", action: open)
                        .disabled(entry.failure != nil).accessibilityLabel("\(entry.title)を開く")
                    Spacer()
                    if let delete {
                        Button("削除", systemImage: "trash", action: delete).accessibilityLabel("\(entry.title)を削除")
                    }
                }
            }
        }
    }
}

struct RecentSessionsView: View {
    let library: SessionsLibrary
    let showAll: () -> Void
    let open: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("最近保存したセッション").font(.title3.weight(.semibold))
                Spacer()
                Button("すべて見る", action: showAll)
            }
            if let error = library.error { Text(error).foregroundStyle(DesignTokens.warning).font(.callout) }
            if library.recent.isEmpty {
                Text("明示的に保存した会議と字幕が、ここに表示されます。")
                    .foregroundStyle(DesignTokens.secondary)
            }
            ForEach(library.recent) { entry in
                SavedSessionRow(entry: entry, open: { open(entry.id) })
            }
        }
        .disabled(library.isBusy)
    }
}

struct SessionSaveControls: View {
    let library: SessionsLibrary
    let snapshot: SessionSnapshot?
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { saveButton; status }
                VStack(alignment: .leading, spacing: 8) { saveButton; status }
            }
            Text("発話・訳文・完成したAI出力・引用抜粋をこのMacに保存します。音声は保存しません。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            if let error = library.error { Text(error).font(.caption).foregroundStyle(DesignTokens.warning) }
        }
    }

    private var saveButton: some View {
        Button(snapshot.flatMap { library.savedSnapshots[$0.id] } == nil ? "このMacに保存" : "変更を再保存",
               systemImage: "folder.badge.plus", action: save)
            .buttonStyle(.borderedProminent)
            .disabled(library.isBusy || snapshot == nil || snapshot.map(library.matches) == true)
    }
    private var status: some View {
        Text(library.isBusy ? "処理中…" : library.status(for: snapshot)).font(.caption).foregroundStyle(DesignTokens.secondary)
    }
}
