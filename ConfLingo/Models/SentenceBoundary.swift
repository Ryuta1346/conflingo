import Foundation

/// 確定セグメントが文末で終わっているかの判定。翻訳単位のバッファ flush 条件に使う。
/// "Dr." 等の略語で早期 flush する可能性は許容する（実害は翻訳単位が短くなるだけ）。
enum SentenceBoundary {
    private static let terminators: Set<Character> = [".", "?", "!", "…", "。", "？", "！"]
    private static let trailing: Set<Character> = [
        "\"", "'", "”", "’", ")", "）", "]", "」", "』", "›", "»",
    ]

    static func endsSentence(_ text: String) -> Bool {
        var rest = Substring(text)
        while let last = rest.last, last.isWhitespace || trailing.contains(last) {
            rest = rest.dropLast()
        }
        guard let last = rest.last else { return false }
        return terminators.contains(last)
    }
}
