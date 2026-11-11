import Foundation
import Observation

@MainActor
@Observable
final class SessionsLibrary {
    private let files: SessionFiles
    private(set) var entries: [SessionListEntry] = []
    private(set) var selected: SavedSession?
    private(set) var pendingDelete: SessionListEntry?
    private(set) var isBusy = false
    private(set) var error: String?
    private(set) var savedSnapshots: [UUID: SessionSnapshot] = [:]
    var query = ""

    init(files: SessionFiles) { self.files = files }

    static func make(preview: Bool) -> SessionsLibrary {
        let root: URL
        let environment = ProcessInfo.processInfo.environment
        if preview || environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("ConfLingo-Sessions-Preview", isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ConfLingo/Sessions", isDirectory: true)
        }
        return SessionsLibrary(files: SessionFiles(directory: root))
    }

    var filtered: [SessionListEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? entries : entries.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    var recent: [SessionListEntry] { Array(entries.filter { $0.failure == nil }.prefix(5)) }

    func matches(_ snapshot: SessionSnapshot) -> Bool { savedSnapshots[snapshot.id] == snapshot }

    func status(for snapshot: SessionSnapshot?) -> String {
        guard let snapshot else { return "停止・終了後にこのMacへ保存できます。自動保存はオフです。" }
        if matches(snapshot) { return "このMacに保存済み" }
        return savedSnapshots[snapshot.id] == nil ? "このMacには未保存" : "保存後に変更あり・再保存が必要です"
    }

    func reload() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { entries = try await files.list() } catch { self.error = "一覧を読み込めません。\(error.localizedDescription)" }
    }

    func save(_ snapshot: SessionSnapshot) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let saved = try await files.save(snapshot)
            savedSnapshots[snapshot.id] = snapshot
            let entry = SessionListEntry(id: saved.id, title: snapshot.title, kind: snapshot.kind,
                                         startedAt: snapshot.startedAt, updatedAt: saved.updatedAt, failure: nil)
            entries.removeAll { $0.id == saved.id }
            entries.insert(entry, at: 0)
            if selected?.id == saved.id { selected = saved }
        } catch { self.error = "保存に失敗しました。前回の保存版と現在の内容は保持しています。\(error.localizedDescription)" }
    }

    func open(_ id: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        selected = nil
        defer { isBusy = false }
        do { selected = try await files.load(id) } catch { self.error = "開けませんでした。\(error.localizedDescription)" }
    }

    func closeDetail() { if !isBusy { selected = nil } }
    func requestDelete(_ entry: SessionListEntry) { if !isBusy { pendingDelete = entry } }
    func cancelDelete() { pendingDelete = nil }

    func confirmDelete(_ confirmed: SessionListEntry? = nil) async {
        guard !isBusy, let entry = confirmed ?? pendingDelete else { return }
        pendingDelete = nil
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            try await files.delete(entry.id)
            entries.removeAll { $0.id == entry.id }
            savedSnapshots[entry.id] = nil
            if selected?.id == entry.id { selected = nil }
        } catch { self.error = "削除できませんでした。保存した内容は保持しています。\(error.localizedDescription)" }
    }
}
