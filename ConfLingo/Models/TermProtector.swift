import Foundation

/// 翻訳前に専門用語・固有名詞をプレースホルダへ置換し、翻訳後に復元する。
/// Apple Translation framework に glossary（do-not-translate）機能がないための前後処理。
enum TermProtector {
    /// プレースホルダ形式。翻訳エンジンに崩されにくい形式を実機検証で決定し、ここだけ差し替える。
    static func placeholder(for index: Int) -> String { "⟦\(index)⟧" }

    /// 用語をプレースホルダに置換し、復元用マッピング（プレースホルダ → ソース上の実際の表記）を返す。
    /// 最長一致優先・大文字小文字無視・ASCII 英数字の単語境界を考慮する。
    static func mask(_ text: String, terms: [String]) -> (masked: String, mapping: [String: String]) {
        let sortedTerms = terms.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        guard !text.isEmpty, !sortedTerms.isEmpty else { return (text, [:]) }

        // 最長の用語から順に占有範囲を確定し、重複マッチを防ぐ
        var claimed: [Range<String.Index>] = []
        for term in sortedTerms {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: term, options: .caseInsensitive, range: searchRange) {
                searchRange = found.upperBound..<text.endIndex
                guard hasWordBoundary(text, found) else { continue }
                guard !claimed.contains(where: { $0.overlaps(found) }) else { continue }
                claimed.append(found)
            }
        }
        guard !claimed.isEmpty else { return (text, [:]) }

        // 出現順に番号を振り、マッチ間のテキストを連結して組み立てる
        var parts: [String] = []
        var mapping: [String: String] = [:]
        var cursor = text.startIndex
        for (index, range) in claimed.sorted(by: { $0.lowerBound < $1.lowerBound }).enumerated() {
            let token = placeholder(for: index)
            parts.append(String(text[cursor..<range.lowerBound]))
            parts.append(token)
            mapping[token] = String(text[range])
            cursor = range.upperBound
        }
        parts.append(String(text[cursor...]))
        return (parts.joined(), mapping)
    }

    /// 翻訳結果中のプレースホルダを元の用語に復元する。
    /// 翻訳エンジンに崩されて見つからないトークンは無視する（翻訳文をそのまま残す）。
    static func unmask(_ translated: String, mapping: [String: String]) -> String {
        var result = translated
        for (token, original) in mapping {
            result = result.replacingOccurrences(of: token, with: original)
        }
        return result
    }

    /// マッチ端と隣接文字が共に ASCII 英数字なら単語境界なしとみなす
    /// （"skill" が "skillful" にマッチするのを防ぐ。日本語・記号の隣接は境界として扱う）。
    private static func hasWordBoundary(_ text: String, _ range: Range<String.Index>) -> Bool {
        func isWordChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        if range.lowerBound > text.startIndex,
           isWordChar(text[text.index(before: range.lowerBound)]),
           isWordChar(text[range.lowerBound]) {
            return false
        }
        if range.upperBound < text.endIndex,
           isWordChar(text[range.upperBound]),
           isWordChar(text[text.index(before: range.upperBound)]) {
            return false
        }
        return true
    }
}
