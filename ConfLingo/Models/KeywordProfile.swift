import Foundation

/// 名前付きの専門用語キーワードプロファイル。
/// 用途（会議・登壇・案件など）ごとに用語辞書を分けて切り替えるための単位。
/// keywords は KeywordParser がパースする生の文字列（"term=訳語, ..." 形式）を保持する。
struct KeywordProfile: Identifiable, Codable, Equatable, Sendable {
    /// Identifiable の安定キー。ForEach / Binding の同一性に用いるため不変。
    let id: UUID
    var name: String
    var keywords: String

    init(id: UUID = UUID(), name: String, keywords: String) {
        self.id = id
        self.name = name
        self.keywords = keywords
    }
}
