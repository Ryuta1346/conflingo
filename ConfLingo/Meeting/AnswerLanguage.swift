import Foundation

enum AnswerLanguage: String, CaseIterable, Sendable, Codable {
    case japanese = "ja"
    case english = "en"

    var label: String { self == .japanese ? "日本語" : "English" }
}
