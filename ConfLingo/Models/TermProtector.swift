import Foundation

/// 翻訳前に専門用語・固有名詞をプレースホルダへ置換し、翻訳後に復元する。
/// Apple Translation framework に glossary（do-not-translate）機能がないための前後処理。
enum TermProtector {
    /// プレースホルダ形式。翻訳エンジンに崩されにくい形式を実機検証で決定し、ここだけ差し替える。
    static func placeholder(for index: Int) -> String { "⟦\(index)⟧" }

    /// 用語をプレースホルダに置換し、復元用マッピング（プレースホルダ → ソース上の実際の表記）を返す。
    /// 最長一致優先・大文字小文字無視・ASCII 英数字の単語境界を考慮する。
    static func mask(_ text: String, terms: [String]) -> (masked: String, mapping: [String: String]) {
        mask(text, glossary: terms.map { KeywordParser.GlossaryEntry(term: $0, target: nil) })
    }

    /// glossary 版。訳語指定あり（target non-nil）の用語は復元時に訳語へ置換され、
    /// 指定なしはソース上の実際の表記を維持する。
    static func mask(
        _ text: String,
        glossary: [KeywordParser.GlossaryEntry]
    ) -> (masked: String, mapping: [String: String]) {
        let sortedEntries = glossary.filter { !$0.term.isEmpty }.sorted { $0.term.count > $1.term.count }
        guard !text.isEmpty, !sortedEntries.isEmpty else { return (text, [:]) }

        // 最長の用語から順に占有範囲を確定し、重複マッチを防ぐ
        var claimed: [(range: Range<String.Index>, restoration: String)] = []
        for entry in sortedEntries {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: entry.term, options: .caseInsensitive, range: searchRange) {
                searchRange = found.upperBound..<text.endIndex
                guard hasWordBoundary(text, found) else { continue }
                guard !claimed.contains(where: { $0.range.overlaps(found) }) else { continue }
                claimed.append((found, entry.target ?? String(text[found])))
            }
        }
        guard !claimed.isEmpty else { return (text, [:]) }

        // 出現順に番号を振り、マッチ間のテキストを連結して組み立てる
        var parts: [String] = []
        var mapping: [String: String] = [:]
        var cursor = text.startIndex
        for (index, match) in claimed.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }).enumerated() {
            let token = placeholder(for: index)
            parts.append(String(text[cursor..<match.range.lowerBound]))
            parts.append(token)
            mapping[token] = match.restoration
            cursor = match.range.upperBound
        }
        parts.append(String(text[cursor...]))
        return (parts.joined(), mapping)
    }

    /// unmask の結果。`unresolvedTokens` が非空なら翻訳エンジンがプレースホルダを
    /// 復元不能な形に崩した（または消した）ことを示す。呼び出し側で再翻訳等のフォールバックに使う。
    struct UnmaskResult: Equatable {
        let text: String
        let unresolvedTokens: [String]
    }

    /// 翻訳結果中のプレースホルダを元の用語（または指定訳語）に復元する。
    /// 完全一致で見つからないトークンは寛容パス（崩れトークンの正規化マッチ）で復元を試み、
    /// それでも残ったものを `unresolvedTokens` として報告する。
    static func unmask(_ translated: String, mapping: [String: String]) -> UnmaskResult {
        var result = translated
        var unresolved: Set<String> = []
        for (token, replacement) in mapping {
            if result.contains(token) {
                result = result.replacingOccurrences(of: token, with: replacement)
            } else {
                unresolved.insert(token)
            }
        }
        if !unresolved.isEmpty {
            (result, unresolved) = recoverBrokenTokens(in: result, mapping: mapping, unresolved: unresolved)
        }
        return UnmaskResult(text: result, unresolvedTokens: unresolved.sorted())
    }

    /// Regex は Sendable 非準拠だが、生成後に変異しないため共有しても安全
    nonisolated(unsafe) private static let brokenTokenPattern = /[⟦〚\[]{1,2}\s*([0-9０-９]+)\s*[⟧〛\]]{1,2}/

    /// 寛容パス。翻訳エンジンに崩されたトークン（全角数字化・括弧の置換/二重化・空白挿入）を
    /// index 正規化で特定し、未解決のものだけ復元する。
    /// mapping にない index（訳文中の正当な [1] 等）と復元済み index は誤食しない。
    private static func recoverBrokenTokens(
        in text: String,
        mapping: [String: String],
        unresolved: Set<String>
    ) -> (String, Set<String>) {
        var result = text
        var remaining = unresolved
        var searchStart = result.startIndex
        while !remaining.isEmpty,
              let match = result[searchStart...].firstMatch(of: brokenTokenPattern) {
            let normalizedDigits = String(match.1.map { c -> Character in
                if let value = c.wholeNumberValue, ("０"..."９").contains(c) {
                    return Character(String(value))
                }
                return c
            })
            guard let index = Int(normalizedDigits) else { break }
            let token = placeholder(for: index)
            // 未解決トークンに対応する index のみ復元対象（範囲外・復元済みはスキップして先へ進む）
            guard remaining.contains(token), let replacement = mapping[token] else {
                searchStart = match.range.upperBound
                continue
            }
            // replaceSubrange で String.Index が無効化されるため、走査位置はオフセットで保持する
            let offset = result.distance(from: result.startIndex, to: searchStart)
            result.replaceSubrange(match.range, with: replacement)
            searchStart = result.index(result.startIndex, offsetBy: offset)
            remaining.remove(token)
        }
        return (result, remaining)
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
