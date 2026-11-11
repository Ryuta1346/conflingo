import CryptoKit
import Foundation

struct KnowledgeArchive: Codable, Equatable, Sendable {
    struct Document: Codable, Equatable, Sendable {
        let document: KnowledgeDocument
        let body: String
    }
    let documents: [Document]
    var isRepository: Bool { documents.first?.document.source != nil }
    var title: String { documents.first.map { $0.document.source?.name ?? $0.document.title } ?? "資料" }
    var kind: String { isRepository ? "リポジトリ" : "文書" }

    static func hash(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func validate() throws {
        guard !documents.isEmpty, documents.count <= (isRepository ? 1_000 : 1),
              Set(documents.map { $0.document.id }).count == documents.count else { throw LibraryFailure.invalid }
        var paths: Set<String> = []
        var characters = 0
        var bytes = 0
        let source = documents[0].document.source
        for item in documents {
            let doc = item.document
            guard !doc.title.isEmpty, doc.title.count <= 200, doc.importedAt.timeIntervalSince1970.isFinite,
                  doc.characterCount == item.body.count, !item.body.contains("\0"),
                  !item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  item.body.count <= 100_000, item.body.utf8.count <= 1_048_576 else { throw LibraryFailure.invalid }
            characters += item.body.count
            bytes += item.body.utf8.count
            if let repo = doc.source {
                let parts = repo.path.split(separator: "/", omittingEmptySubsequences: false)
                guard isRepository, repo.snapshotID == source?.snapshotID, repo.name == source?.name,
                      !repo.name.isEmpty, repo.name.count <= 200,
                      !repo.path.isEmpty, repo.path.count <= 1_024, !repo.path.contains("\0"),
                      parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                      paths.insert(repo.path).inserted, repo.contentHash == Self.hash(item.body) else { throw LibraryFailure.invalid }
            } else if isRepository { throw LibraryFailure.invalid }
        }
        guard characters <= (isRepository ? 5_000_000 : 100_000), bytes <= (isRepository ? 20 * 1_048_576 : 1_048_576) else {
            throw LibraryFailure.limit
        }
    }
}

struct SavedKnowledge: Codable, Equatable, Identifiable, Sendable {
    let version: Int
    let id: UUID
    let revision: UUID
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let content: KnowledgeArchive

    func validate() throws {
        guard version == 1 else { throw LibraryFailure.unsupported }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 200,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              updatedAt >= createdAt else { throw LibraryFailure.invalid }
        try content.validate()
    }

    var entry: KnowledgeLibraryEntry {
        .init(id: id, revision: revision, title: title, kind: content.kind,
              count: content.documents.count, updatedAt: updatedAt, failure: nil)
    }
}

struct KnowledgeLibraryEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let revision: UUID?
    let title: String
    let kind: String
    let count: Int
    let updatedAt: Date?
    let failure: String?
}

enum LibraryFailure: Error, LocalizedError {
    case invalid, unsupported, unsafe, limit, changed, duplicate, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "保存資料が不正です。元の保存ファイルは保持しています。"
        case .unsupported: "この資料の保存形式には対応していません。"
        case .unsafe: "保存資料にアクセスできません。ファイルとアクセス権を確認してください。"
        case .limit: "資料ライブラリの上限を超えています（100項目・合計200 MiB・1項目64 MiB）。"
        case .changed: "保存資料が更新または削除されました。一覧を読み直して選択してください。"
        case .duplicate: "この資料は会議に追加済みです。新版を使う場合は準備画面で取り外してから追加してください。"
        case .unavailable: "会議の準備中に、他の処理が終わってから操作してください。"
        }
    }
}
