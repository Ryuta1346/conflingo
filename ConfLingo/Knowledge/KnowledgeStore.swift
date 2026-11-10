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
    private var revision = UUID()
    private var consentRevision = UUID()
    private var searchID = UUID()
    private var mutationID: UUID?
    private let lookup: @MainActor (KnowledgeIndex, String) async throws -> [KnowledgeReference]

    init(lookup: (@MainActor (KnowledgeIndex, String) async throws -> [KnowledgeReference])? = nil) {
        self.lookup = lookup ?? { index, query in try await index.search(query) }
    }
    @ObservationIgnored var onChange: (() -> Void)?

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
        do {
            let document = try await operation(index)
            guard mutationID == mutation else { return }
            documents.append(document)
            message = "資料を取り込みました。この会議の終了後も、破棄するまで参照できます。"
        } catch {
            guard mutationID == mutation else { return }
            message = (error as? KnowledgeFailure ?? .unreadable).localizedDescription
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
        invalidate()
        mutationID = nil
        index = KnowledgeIndex()
        documents = []
        permitted = false
        isBusy = false
        message = ""
    }

    private func invalidate() {
        revision = UUID()
        searchID = UUID()
        results = []
        searchState = .idle
        onChange?()
    }
}
