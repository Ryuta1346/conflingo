import Foundation

/// 処理結果を表示するための一時状態。保存データには含めない。
struct UserMessage: Equatable, Sendable {
    enum Kind: CaseIterable, Sendable { case information, success, warning, failure }
    let kind: Kind
    let text: String
    var details: String?

    init(_ kind: Kind, _ text: String, details: String? = nil) {
        self.kind = kind
        self.text = text
        self.details = details?.isEmpty == false ? details : nil
    }
}
