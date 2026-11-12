import SwiftUI

struct MeetingLibraryControls: View {
    @Bindable var meeting: MeetingWorkspace
    @Bindable var library: KnowledgeLibrary
    let fontSize: Double
    @State private var choosing = false
    @State private var saving: LibrarySaveChoice?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("ライブラリから追加", systemImage: "books.vertical") { choosing = true }
                .disabled(!library.canUse(meeting))
            ForEach(meeting.knowledge.documents.filter { $0.source == nil }) { document in
                HStack {
                    Button("ライブラリに保存：\(document.title)") {
                        saving = LibrarySaveChoice(documentID: document.id, title: meeting.knowledge.librarySources[document.id]?.title ?? document.title, count: 1, repository: false)
                    }
                    .disabled(!library.canUse(meeting))
                    if let entry = meeting.knowledge.librarySources[document.id] { savedLabel(entry) }
                }
            }
            if let first = meeting.knowledge.documents.first(where: { $0.source != nil }) {
                Button("リポジトリ資料をライブラリに保存") {
                    saving = LibrarySaveChoice(documentID: nil, title: meeting.knowledge.librarySources[first.id]?.title ?? first.source?.name ?? first.title,
                        count: meeting.knowledge.documents.filter { $0.source != nil }.count, repository: true)
                }.disabled(!library.canUse(meeting))
                if let entry = meeting.knowledge.librarySources[first.id] { savedLabel(entry) }
            }
        }
        .sheet(isPresented: $choosing) {
            VStack(spacing: 0) {
                KnowledgeLibraryView(library: library, fontSize: fontSize) { entry in
                    Task { if await library.attach(entry.id, to: meeting) { choosing = false; library.close() } }
                }
                HStack { Spacer(); Button("閉じる") { choosing = false; library.close() }.keyboardShortcut(.cancelAction) }
                    .padding().disabled(library.isBusy)
            }
            .frame(minWidth: 480, idealWidth: 640, minHeight: 400, idealHeight: 560)
            .interactiveDismissDisabled(library.isBusy)
        }
        .sheet(item: $saving) { choice in
            KnowledgeSaveView(meeting: meeting, library: library, choice: choice)
        }
    }

    private func savedLabel(_ entry: KnowledgeLibraryEntry) -> some View {
        let exists = library.entries.contains { $0.id == entry.id }
        return Text("\(entry.title) · 保存版 \(entry.revision?.uuidString.prefix(8) ?? "")\(exists ? "" : "（ライブラリ削除済み）")")
            .font(.caption).foregroundStyle(DesignTokens.secondary)
    }
}

private struct LibrarySaveChoice: Identifiable {
    let id = UUID()
    let documentID: UUID?
    let title: String
    let count: Int
    let repository: Bool
}

private struct KnowledgeSaveView: View {
    @Bindable var meeting: MeetingWorkspace
    @Bindable var library: KnowledgeLibrary
    let choice: LibrarySaveChoice
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var replacementID: UUID?

    private var targets: [KnowledgeLibraryEntry] {
        library.entries.filter { $0.failure == nil && $0.kind == (choice.repository ? "リポジトリ" : "文書") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("資料をライブラリに保存").font(.title2.bold())
            Text("\(choice.title) · \(choice.count)文書")
            Text("選んだ資料の本文をこのMacに保持します。会議を破棄しても残ります。元ファイルとAI送信許可は変更しません。")
                .font(.callout).foregroundStyle(DesignTokens.secondary)
            TextField("保存名", text: $title).textFieldStyle(.roundedBorder).accessibilityLabel("資料の保存名")
            Picker("更新先", selection: $replacementID) {
                Text("この資料の保存先（初回は新規）").tag(nil as UUID?)
                ForEach(targets) { entry in Text(entry.title).tag(Optional(entry.id)) }
            }
            if let target = targets.first(where: { $0.id == replacementID }) {
                Text("「\(target.title)」を、この\(choice.count)文書で置き換えます。使用中の会議と過去の引用は変更しません。")
                    .font(.callout).foregroundStyle(DesignTokens.warning)
            }
            if let error = library.error { Text(error).font(.callout).foregroundStyle(DesignTokens.warning) }
            HStack {
                if library.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Button("キャンセル", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(replacementID == nil ? "このMacに保存" : "確認して更新") {
                    let target = targets.first { $0.id == replacementID }
                    Task {
                        if await library.save(from: meeting, documentID: choice.documentID, title: title, replacing: target) { dismiss() }
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 200)
            }
        }
        .padding(24).frame(minWidth: 440, idealWidth: 540)
        .disabled(library.isBusy)
        .interactiveDismissDisabled(library.isBusy)
        .task { title = choice.title; await library.reload() }
    }
}
