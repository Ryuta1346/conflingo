import Foundation
import Observation

@MainActor
@Observable
final class KnowledgeStore {
    enum SearchState: Equatable { case idle, searching, found, empty, failed }
    private(set) var documents: [KnowledgeDocument] = []
    private(set) var results: [KnowledgeReference] = []
    private(set) var searchState: SearchState = .idle
    private(set) var isBusy = false
    private(set) var message = ""
    private(set) var permitted = false
    private var index = KnowledgeIndex()
    private(set) var librarySources: [UUID: KnowledgeLibraryEntry] = [:]
    private(set) var revision = UUID()
    private(set) var importGeneration = UUID()
    private var consentRevision = UUID()
    private var searchID = UUID()
    private var mutationID: UUID?
    private let lookup: @MainActor (KnowledgeIndex, String) async throws -> [KnowledgeReference]

    init(lookup: (@MainActor (KnowledgeIndex, String) async throws -> [KnowledgeReference])? = nil) {
        self.lookup = lookup ?? { index, query in try await index.search(query) }
    }
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onInvalidation: (() -> Void)?
    @ObservationIgnored var onContentChange: (() -> Void)?
    @ObservationIgnored private var repositoryTask: Task<[KnowledgeDocument], Error>?

    var hasRepository: Bool { documents.contains { $0.source != nil } }

    func importRepository(_ scan: RepositoryScan, selected: Set<String>) async {
        guard !isBusy, !hasRepository else { return }
        invalidate()
        let mutation = UUID()
        mutationID = mutation
        isBusy = true
        message = "リポジトリを取り込んでいます…"
        let index = index
        let generation = importGeneration
        let task = Task {
            let snapshot = try await RepositoryImporter.load(scan, selected: selected)
            try Task.checkCancellation()
            return try await index.addRepository(snapshot)
        }
        repositoryTask = task
        do {
            let imported = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard generation == importGeneration, !Task.isCancelled else {
                for document in imported { try? await index.remove(document.id) }
                throw CancellationError()
            }
            guard mutationID == mutation else { return }
            documents += imported
            onContentChange?()
            message = "リポジトリを取り込みました。取り込み時点の作業ツリーをこの会議で参照します。"
        } catch {
            guard mutationID == mutation else { return }
            message = error is CancellationError ? "取り込みを中止しました。" : error.localizedDescription
        }
        repositoryTask = nil
        mutationID = nil
        isBusy = false
    }

    func cancelRepositoryImport() { repositoryTask?.cancel() }

    func cancelPendingImports() {
        importGeneration = UUID()
        repositoryTask?.cancel()
    }

    func contents() async throws -> [KnowledgeArchive.Document] {
        let version = revision
        let result = await index.contents()
        guard version == revision, !isBusy else { throw CancellationError() }
        return result
    }

    func removeRepository() async {
        guard !isBusy, hasRepository else { return }
        invalidate()
        isBusy = true
        let mutation = UUID()
        mutationID = mutation
        do {
            try await index.removeRepository()
            guard mutationID == mutation else { return }
            documents.removeAll { $0.source != nil }
            let remaining = Set(documents.map(\.id))
            librarySources = librarySources.filter { remaining.contains($0.key) }
            onContentChange?()
            message = "リポジトリを取り外しました。生成済みの引用は会議破棄まで残ります。"
        } catch {
            guard mutationID == mutation else { return }
            message = KnowledgeFailure.search.localizedDescription
        }
        mutationID = nil
        isBusy = false
    }

    func retrieveForSummary(_ events: [TranscriptEvent]) async throws -> [KnowledgeReference] {
        try await rankedReferences(events.map(\.text))
    }

    func localReferences(_ text: String) async throws -> [KnowledgeReference] { try await rankedReferences([text]) }

    func retrieveForAutomatic(_ event: TranscriptEvent) async throws -> [KnowledgeReference] {
        try await rankedReferences([String(event.text.prefix(12_000))])
    }

    private func rankedReferences(_ texts: [String]) async throws -> [KnowledgeReference] {
        guard !isBusy else { throw KnowledgeFailure.search }
        let version = revision
        var scores: [UUID: Double] = [:]
        var references: [UUID: KnowledgeReference] = [:]
        for text in texts {
            var start = text.startIndex
            while start < text.endIndex {
                try Task.checkCancellation()
                let end = text.index(start, offsetBy: 2_000, limitedBy: text.endIndex) ?? text.endIndex
                let hits = try await lookup(index, String(text[start..<end]))
                guard revision == version, !isBusy else { throw CancellationError() }
                for (rank, reference) in hits.enumerated() {
                    scores[reference.id, default: 0] += 1 / Double(rank + 1)
                    references[reference.id] = reference
                }
                start = end
            }
        }
        try Task.checkCancellation()
        return references.values.sorted {
            let left = scores[$0.id, default: 0], right = scores[$1.id, default: 0]
            if left != right { return left > right }
            if $0.displayTitle != $1.displayTitle { return $0.displayTitle < $1.displayTitle }
            return $0.characterOffset < $1.characterOffset
        }.prefix(5).map { $0 }
    }

    func archive(documentID: UUID?) async throws -> KnowledgeArchive {
        guard !isBusy else { throw LibraryFailure.unavailable }
        let version = revision
        let content = try await index.archive(documentID: documentID)
        guard version == revision else { throw CancellationError() }
        return content
    }

    func markSaved(_ saved: SavedKnowledge) {
        let ids = Set(documents.map(\.id))
        for item in saved.content.documents where ids.contains(item.document.id) {
            librarySources[item.document.id] = saved.entry
        }
    }

    func restore(_ saved: SavedKnowledge) async throws {
        guard !isBusy else { throw LibraryFailure.unavailable }
        try saved.validate()
        guard !librarySources.values.contains(where: { $0.id == saved.id }) else { throw LibraryFailure.duplicate }
        invalidate()
        let mutation = UUID()
        mutationID = mutation
        isBusy = true
        defer { if mutationID == mutation { mutationID = nil; isBusy = false } }
        let index = index
        let generation = importGeneration
        let restored = try await index.restore(saved.content)
        guard generation == importGeneration, !Task.isCancelled else {
            for document in restored { try? await index.remove(document.id) }
            throw CancellationError()
        }
        guard mutationID == mutation else { throw CancellationError() }
        documents += restored
        markSaved(saved)
        onContentChange?()
        message = "保存資料を追加しました。資料の送信許可を確認してください。"
    }

    func setPermission(_ value: Bool) {
        guard permitted != value else { return }
        permitted = value
        consentRevision = UUID()
        onChange?()
    }

    func add(url: URL) async {
        await importDocument { try await $0.add(url: url) }
    }

    func add(data: Data, filename: String) async {
        await importDocument { try await $0.add(data: data, filename: filename) }
    }

    private func importDocument(_ operation: (KnowledgeIndex) async throws -> KnowledgeDocument) async {
        guard !isBusy else { return }
        invalidate()
        let mutation = UUID()
        mutationID = mutation
        isBusy = true
        message = "資料を取り込んでいます…"
        let index = index
        let generation = importGeneration
        do {
            let document = try await operation(index)
            guard generation == importGeneration, !Task.isCancelled else {
                try? await index.remove(document.id)
                throw CancellationError()
            }
            guard mutationID == mutation else { return }
            documents.append(document)
            onContentChange?()
            message = "資料を取り込みました。この会議の終了後も、破棄するまで参照できます。"
        } catch {
            guard mutationID == mutation else { return }
            message = error is CancellationError ? "取り込みを中止しました。" : (error as? KnowledgeFailure ?? .unreadable).localizedDescription
        }
        mutationID = nil
        isBusy = false
    }

    func remove(_ id: UUID) async {
        guard !isBusy, documents.contains(where: { $0.id == id }) else { return }
        invalidate()
        let mutation = UUID()
        mutationID = mutation
        isBusy = true
        do {
            try await index.remove(id)
            guard mutationID == mutation else { return }
            documents.removeAll { $0.id == id }
            librarySources[id] = nil
            onContentChange?()
            message = "資料を取り外しました。既存の回答にある引用は会議破棄まで残ります。"
        } catch {
            guard mutationID == mutation else { return }
            message = KnowledgeFailure.search.localizedDescription
        }
        mutationID = nil
        isBusy = false
    }

    func search(_ text: String) async {
        let id = UUID()
        searchID = id
        let version = revision
        results = []
        guard !isBusy else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { searchState = .idle; return }
        searchState = .searching
        do {
            let hits = try await lookup(index, text)
            guard searchID == id, revision == version else { return }
            results = hits
            searchState = hits.isEmpty ? .empty : .found
        } catch {
            guard searchID == id, revision == version else { return }
            searchState = .failed
        }
    }

    func retrieve(_ question: String) async throws -> [KnowledgeReference] {
        guard permitted else { return [] }
        guard !isBusy else { throw KnowledgeFailure.search }
        let version = revision
        let consent = consentRevision
        let results = try await lookup(index, question)
        guard revision == version, consentRevision == consent, permitted, !Task.isCancelled else { throw CancellationError() }
        return Array(results.prefix(5))
    }

    func reset() {
        cancelPendingImports()
        repositoryTask?.cancel()
        repositoryTask = nil
        invalidate()
        mutationID = nil
        index = KnowledgeIndex()
        documents = []
        librarySources = [:]
        permitted = false
        isBusy = false
        message = ""
        onContentChange?()
    }

    @ObservationIgnored private var invalidationObservers: [() -> Void] = []
    func observeInvalidation(_ action: @escaping () -> Void) { invalidationObservers.append(action) }

    private func invalidate() {
        revision = UUID()
        onInvalidation?()
        for observer in invalidationObservers { observer() }
        searchID = UUID()
        results = []
        searchState = .idle
        onChange?()
    }
}
