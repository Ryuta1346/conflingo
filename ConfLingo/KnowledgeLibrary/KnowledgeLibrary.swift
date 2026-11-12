import Foundation
import Observation

@MainActor
@Observable
final class KnowledgeLibrary {
    private let files: KnowledgeLibraryFiles
    private let load: @MainActor (UUID) async throws -> SavedKnowledge
    private(set) var entries: [KnowledgeLibraryEntry] = []
    private(set) var selected: SavedKnowledge?
    private(set) var isBusy = false
    private(set) var error: String?
    var query = ""

    init(files: KnowledgeLibraryFiles, load: (@MainActor (UUID) async throws -> SavedKnowledge)? = nil) {
        self.files = files
        self.load = load ?? { try await files.load($0) }
    }

    static func make(preview: Bool) -> KnowledgeLibrary {
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
        let root = preview || testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ConfLingo-KnowledgeLibrary-Preview")
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ConfLingo/KnowledgeLibrary")
        return KnowledgeLibrary(files: KnowledgeLibraryFiles(directory: root))
    }

    var filtered: [KnowledgeLibraryEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? entries : entries.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    func reload() async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do { entries = try await files.list() } catch { self.error = "一覧を読み込めません。\(error.localizedDescription)" }
    }

    func open(_ id: UUID) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        selected = nil
        defer { isBusy = false }
        do { selected = try await load(id) } catch { self.error = "資料を開けません。\(error.localizedDescription)" }
    }

    func close() { if !isBusy { selected = nil } }

    func delete(_ entry: KnowledgeLibraryEntry) async {
        guard !isBusy else { return }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            // A confirmation for an old revision must not delete its replacement.
            if let revision = entry.revision, try await files.load(entry.id).revision != revision { throw LibraryFailure.changed }
            try await files.delete(entry.id)
            entries.removeAll { $0.id == entry.id }
            if selected?.id == entry.id { selected = nil }
        } catch { self.error = "削除できませんでした。\(error.localizedDescription)" }
    }

    func canUse(_ meeting: MeetingWorkspace) -> Bool { !isBusy && meeting.canEditKnowledge }

    func save(from meeting: MeetingWorkspace, documentID: UUID?, title: String,
              replacing replacement: KnowledgeLibraryEntry? = nil) async -> Bool {
        guard canUse(meeting) else { error = LibraryFailure.unavailable.localizedDescription; return false }
        meeting.isUsingLibrary = true
        defer { meeting.isUsingLibrary = false }
        return await save(from: meeting.knowledge, documentID: documentID, title: title, replacing: replacement)
    }

    func save(from knowledge: KnowledgeStore, documentID: UUID?, title: String,
              replacing replacement: KnowledgeLibraryEntry? = nil) async -> Bool {
        guard !isBusy, !knowledge.isBusy else { return false }
        isBusy = true
        error = nil
        defer { isBusy = false }
        let revision = knowledge.revision
        let generation = knowledge.importGeneration
        do {
            let content = try await knowledge.archive(documentID: documentID)
            guard revision == knowledge.revision, generation == knowledge.importGeneration, !Task.isCancelled else { throw CancellationError() }
            let previous = content.documents.first.flatMap { knowledge.librarySources[$0.document.id] }
            let target = replacement ?? previous.flatMap { old in entries.contains { $0.id == old.id } ? old : nil }
            let saved = try await files.save(content, title: title, replacing: target?.id, expectedRevision: target?.revision)
            upsert(saved.entry)
            if selected?.id == saved.id { selected = saved }
            if revision == knowledge.revision, generation == knowledge.importGeneration { knowledge.markSaved(saved) }
            return true
        } catch { self.error = "保存できませんでした。前回の保存版を保持します。\(error.localizedDescription)"; return false }
    }

    func attach(_ id: UUID, to meeting: MeetingWorkspace) async -> Bool {
        guard canUse(meeting) else { error = LibraryFailure.unavailable.localizedDescription; return false }
        meeting.isUsingLibrary = true
        defer { meeting.isUsingLibrary = false }
        let result = await attach(id, to: meeting.knowledge)
        if result { meeting.setKnowledgeAllowed(false); meeting.setAutomaticKnowledgeAllowed(false) }
        return result
    }

    func attach(_ id: UUID, to knowledge: KnowledgeStore) async -> Bool {
        guard !isBusy, !knowledge.isBusy else { return false }
        isBusy = true
        error = nil
        defer { isBusy = false }
        let revision = knowledge.revision
        let generation = knowledge.importGeneration
        do {
            let saved = try await load(id)
            guard revision == knowledge.revision, generation == knowledge.importGeneration, !Task.isCancelled else { throw CancellationError() }
            try await knowledge.restore(saved)
            upsert(saved.entry)
            knowledge.setPermission(false)
            return true
        } catch { self.error = "追加できませんでした。\(error.localizedDescription)"; return false }
    }

    private func upsert(_ entry: KnowledgeLibraryEntry) {
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }
}
