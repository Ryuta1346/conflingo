import Foundation

struct KnowledgeDocument: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let importedAt: Date
    let characterCount: Int
}

struct KnowledgeReference: Identifiable, Equatable, Sendable {
    let id: UUID
    let documentID: UUID
    let title: String
    let importedAt: Date
    let startLine: Int
    let characterOffset: Int
    let snippet: String

    var location: String { "\(startLine)行目から（文書先頭から\(characterOffset + 1)文字目）" }
}

enum KnowledgeFailure: Error, LocalizedError, Equatable {
    case unsupported, encoding, empty, limit, duplicate, unreadable, search

    var errorDescription: String? {
        switch self {
        case .unsupported: "UTF-8のMarkdown（.md）またはText（.txt）を選択してください。"
        case .encoding: "UTF-8のテキストとして読み込めませんでした。"
        case .empty: "資料に本文がありません。"
        case .limit: "資料の上限を超えています。20文書、1文書1 MiB・10万文字、合計50万文字までです。"
        case .duplicate: "同じ本文の資料は取り込み済みです。"
        case .unreadable: "資料を読み込めませんでした。ファイルとアクセス権を確認してください。"
        case .search: "資料の検索処理に失敗しました。もう一度操作してください。"
        }
    }
}
