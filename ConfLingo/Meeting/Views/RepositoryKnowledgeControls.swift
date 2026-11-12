import SwiftUI
import AppKit

struct RepositoryKnowledgeControls: View {
    @Bindable var knowledge: KnowledgeStore
    let canEdit: () -> Bool
    let importSelection: (RepositoryScan, Set<String>) async -> Void

    init(meeting: MeetingWorkspace) {
        knowledge = meeting.knowledge
        canEdit = { meeting.canEditKnowledge }
        importSelection = { await meeting.importRepository($0, selected: $1) }
    }

    init(knowledge: KnowledgeStore, canEdit: @escaping () -> Bool,
         importSelection: @escaping (RepositoryScan, Set<String>) async -> Void) {
        self.knowledge = knowledge
        self.canEdit = canEdit
        self.importSelection = importSelection
    }
    @State private var scan: RepositoryScan?
    @State private var selected: Set<String> = []
    @State private var scanning = false
    @State private var error = ""
    @State private var scanTask: Task<Void, Never>?
    @State private var showsRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if canEdit() {
                Button("リポジトリを追加", systemImage: "folder.badge.plus") { chooseFolder() }
                    .disabled(scanning || !canEdit() || knowledge.isBusy || knowledge.hasRepository)
                Text("ローカルのコード・テスト・文書を選びます。1リポジトリ・1,000ファイル・500万文字・20 MiBまで。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
            }
            if scanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("取り込み対象を確認しています…")
                    Button("中止") { scanTask?.cancel() }
                }
            }
            if knowledge.hasRepository {
                Button("リポジトリを取り外す", role: .destructive) { showsRemoval = true }
                    .disabled(!canEdit() || knowledge.isBusy)
            }
            if knowledge.isBusy {
                Button("リポジトリ取り込みを中止") { knowledge.cancelRepositoryImport() }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(DesignTokens.warning) }
        }
        .sheet(item: $scan) { preview in
            RepositorySelectionView(scan: preview, selected: $selected) {
                scan = nil
            } importSelection: {
                let paths = selected
                scan = nil
                Task { if canEdit() { await importSelection(preview, paths) } }
            }
        }
        .alert("リポジトリを取り外しますか？", isPresented: $showsRemoval) {
            Button("キャンセル", role: .cancel) { }
            Button("取り外す", role: .destructive) { Task { if canEdit() { await knowledge.removeRepository() } } }
        } message: {
            Text("検索・送信から除外し、資料を使う生成を停止します。生成済みの引用は会議破棄まで残ります。元ファイルは削除しません。")
        }
        .onChange(of: knowledge.importGeneration) { scanTask?.cancel(); scan = nil }
        .onDisappear { scanTask?.cancel() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "フォルダを選択"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanFolder(url)
    }

    private func scanFolder(_ url: URL) {
        scanTask?.cancel()
        scanning = true
        error = ""
        let generation = knowledge.importGeneration
        scanTask = Task {
            defer { scanning = false }
            do {
                let result = try await RepositoryImporter.scan(url)
                guard !Task.isCancelled, canEdit(), generation == knowledge.importGeneration else { return }
                selected = Set(result.eligible.map(\.path))
                scan = result
            } catch is CancellationError { } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

struct RepositorySelectionView: View {
    let scan: RepositoryScan
    @Binding var selected: Set<String>
    let cancel: () -> Void
    let importSelection: () -> Void
    private var bytes: Int { scan.eligible.filter { selected.contains($0.path) }.reduce(0) { $0 + $1.bytes } }
    private var exceedsLimit: Bool { selected.count > 1_000 || bytes > 20 * 1_048_576 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("取り込むファイルを確認").font(.title2.bold())
            Text(scan.root.lastPathComponent).font(.headline)
            Text("取り込み時点の作業ツリーを参照します。Gitコミットの版とは限りません。選んだ本文はこの会議内で保持します。")
            Text("隠しファイル・依存パッケージ・生成物・既知の認証情報を除外します。.gitignoreの全規則は適用しません。ソース内の秘密情報は対象から外してください。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            HStack {
                Button("すべて選択") { selected = Set(scan.eligible.map(\.path)) }
                Button("すべて解除") { selected = [] }
                Spacer()
                Text("\(selected.count)ファイル · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))")
            }
            if exceedsLimit { Text("上限を超えています。ファイルやフォルダを外してください。").foregroundStyle(DesignTokens.warning) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(scan.entries) { entry in
                        if entry.reason == nil {
                            Toggle(isOn: selection([entry.path])) {
                                Text("\(entry.path) · \(entry.bytes) bytes").textSelection(.enabled)
                            }
                        } else if entry.reason == "フォルダ" {
                            let paths = Set(scan.eligible.filter { $0.path.hasPrefix(entry.path) }.map(\.path))
                            Toggle(entry.path, isOn: selection(paths)).fontWeight(.semibold).disabled(paths.isEmpty)
                        } else {
                            Text("\(entry.path) — \(entry.reason ?? "除外")").font(.caption).foregroundStyle(DesignTokens.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("追加時には外部送信しません。AIで使う際はリポジトリ名・相対パス・位置・抜粋を送信します。文字数上限は読み込み時にも検証します。")
                .font(.caption)
            HStack {
                Button("キャンセル", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("選択したファイルを取り込む", action: importSelection)
                    .buttonStyle(.borderedProminent).disabled(selected.isEmpty || exceedsLimit)
            }
        }.padding(24).frame(minWidth: 440, idealWidth: 640, minHeight: 450, idealHeight: 600)
    }

    private func selection(_ paths: Set<String>) -> Binding<Bool> {
        Binding(get: { !paths.isEmpty && paths.isSubset(of: selected) }, set: { included in
            if included { selected.formUnion(paths) } else { selected.subtract(paths) }
        })
    }
}
