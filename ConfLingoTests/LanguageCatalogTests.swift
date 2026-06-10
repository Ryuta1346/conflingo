import Foundation
import Testing
@testable import ConfLingo

struct LanguageCatalogTests {
    @Test func displayNameForLocaleID() {
        #expect(LanguageCatalog.displayName(for: "en-US").contains("英語"))
        #expect(LanguageCatalog.displayName(for: "ja").contains("日本語"))
        #expect(LanguageCatalog.displayName(for: "zh-Hans").contains("中国語"))
    }

    @Test func displayNameFallsBackToRawID() {
        #expect(LanguageCatalog.displayName(for: "xx-INVALID") == "xx-INVALID")
    }

    @Test func selectableTargetsExcludesSourceLanguage() {
        let targets = [
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "en"),
            Locale.Language(identifier: "ko"),
        ]
        let result = LanguageCatalog.selectableTargets(targets, excludingSourceLocaleID: "en-US")
        #expect(result.map(\.minimalIdentifier) == ["ja", "ko"])
    }

    @Test func selectableTargetsKeepsAllWhenSourceNotIncluded() {
        let targets = [Locale.Language(identifier: "ja"), Locale.Language(identifier: "ko")]
        let result = LanguageCatalog.selectableTargets(targets, excludingSourceLocaleID: "fr-FR")
        #expect(result.count == 2)
    }

    @Test func resolveTargetKeepsCurrentWhenValid() {
        #expect(LanguageCatalog.resolveTarget(current: "ja", sourceLocaleID: "en-US") == "ja")
        #expect(LanguageCatalog.resolveTarget(current: "ko", sourceLocaleID: "ja-JP") == "ko")
    }

    @Test func resolveTargetSwitchesWhenConflictsWithSource() {
        // 認識言語と翻訳先が同一言語になったら自動で振り替える
        #expect(LanguageCatalog.resolveTarget(current: "ja", sourceLocaleID: "ja-JP") == "en")
        #expect(LanguageCatalog.resolveTarget(current: "en", sourceLocaleID: "en-US") == "ja")
    }
}
