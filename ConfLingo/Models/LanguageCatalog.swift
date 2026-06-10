import Foundation

/// 言語選択 UI のための表示名・候補整形ヘルパー。
enum LanguageCatalog {
    private static let displayLocale = Locale(identifier: "ja-JP")

    /// Locale ID / 言語コード（例 "en-US", "ja", "zh-Hans"）の日本語表示名を返す。
    /// 解決できない場合は ID をそのまま返す。
    static func displayName(for identifier: String) -> String {
        displayLocale.localizedString(forIdentifier: identifier) ?? identifier
    }

    /// 翻訳先候補から、認識言語と同一言語を除外する（同一言語ペアは翻訳不可のため）。
    static func selectableTargets(
        _ targets: [Locale.Language],
        excludingSourceLocaleID sourceID: String
    ) -> [Locale.Language] {
        let sourceCode = Locale(identifier: sourceID).language.languageCode?.identifier
        return targets.filter { $0.languageCode?.identifier != sourceCode }
    }

    /// 認識言語の変更後も現在の翻訳先が有効ならそのまま、
    /// 同一言語に衝突したら定番の振り替え先（ja ⇔ en）を返す。
    static func resolveTarget(current: String, sourceLocaleID: String) -> String {
        let sourceCode = Locale(identifier: sourceLocaleID).language.languageCode?.identifier
        let currentCode = Locale.Language(identifier: current).languageCode?.identifier
        guard sourceCode == currentCode else { return current }
        return sourceCode == "ja" ? "en" : "ja"
    }
}
