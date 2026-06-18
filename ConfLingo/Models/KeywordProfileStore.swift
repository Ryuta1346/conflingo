import Foundation
import Observation

/// 複数の名前付きキーワードプロファイルを管理し UserDefaults に永続化する。
/// @AppStorage は配列を持てないため、profiles を JSON 化して単一キーに保存する。
/// 不変条件: `profiles.count >= 1` かつ `selectedID` は必ず profiles に存在する id。
@MainActor
@Observable
final class KeywordProfileStore {
    /// profiles 配列を JSON で保存するキー。
    static let profilesKey = "keywordProfiles"
    /// 選択中プロファイル ID を保存するキー。
    static let selectedIDKey = "selectedKeywordProfileID"
    /// 旧バージョンの単一キーワード文字列（マイグレーション元。削除はしない）。
    static let legacyKeywordsKey = "contextKeywords"
    /// マイグレーションや完全新規時に生成する初期プロファイル名。
    static let defaultProfileName = "デフォルト"

    private let defaults: UserDefaults

    /// didSet で UserDefaults へ自動永続化する。init 内では didSet は発火しない。
    private(set) var profiles: [KeywordProfile] {
        didSet { persistProfiles() }
    }
    private(set) var selectedID: UUID {
        didSet { defaults.set(selectedID.uuidString, forKey: Self.selectedIDKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // マイグレーション/ロードはローカルで完結させてから代入し、初期状態を確定する。
        let loaded = Self.load(from: defaults)
        self.profiles = loaded.profiles
        self.selectedID = loaded.selectedID
        // init 中は didSet が呼ばれないため、マイグレーション結果を明示的に1度永続化する。
        persistProfiles()
        defaults.set(selectedID.uuidString, forKey: Self.selectedIDKey)
    }

    // MARK: - 選択中プロファイル

    /// 選択中プロファイル。selectedID が壊れていれば先頭にフォールバックする。
    var selectedProfile: KeywordProfile {
        profiles.first { $0.id == selectedID } ?? profiles[0]
    }

    /// 選択中プロファイルの配列インデックス（常に有効。先頭フォールバック）。
    private var selectedIndex: Int {
        profiles.firstIndex { $0.id == selectedID } ?? 0
    }

    func select(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    // MARK: - CRUD

    /// 選択中プロファイルの keywords を更新する。id→index を都度引くため配列操作に強い。
    func updateSelectedKeywords(_ keywords: String) {
        let i = selectedIndex
        guard profiles[i].keywords != keywords else { return } // 不要な再永続化を避ける
        profiles[i].keywords = keywords
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        profiles[i].name = trimmed
    }

    /// 新規プロファイルを作成して選択する。
    @discardableResult
    func addProfile(name: String, keywords: String = "") -> KeywordProfile {
        let profile = KeywordProfile(name: uniqueName(name), keywords: keywords)
        profiles.append(profile)
        selectedID = profile.id
        return profile
    }

    /// 指定プロファイルを複製して選択する。
    @discardableResult
    func duplicate(_ id: UUID) -> KeywordProfile? {
        guard let source = profiles.first(where: { $0.id == id }) else { return nil }
        let copy = KeywordProfile(
            name: uniqueName("\(source.name) のコピー"),
            keywords: source.keywords
        )
        profiles.append(copy)
        selectedID = copy.id
        return copy
    }

    /// プロファイルを削除する。最後の1件は削除不可（false を返す）。
    /// 選択中を削除した場合は隣のプロファイルへ選択を移す。
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        guard profiles.count > 1,
              let i = profiles.firstIndex(where: { $0.id == id }) else { return false }
        let wasSelected = (id == selectedID)
        profiles.remove(at: i)
        if wasSelected {
            selectedID = profiles[min(i, profiles.count - 1)].id
        }
        return true
    }

    // MARK: - 永続化 / ロード

    private func persistProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.profilesKey)
    }

    /// 同名が既にあれば " 2", " 3" … と連番を付けて一意化する。
    private func uniqueName(_ base: String) -> String {
        let existing = Set(profiles.map(\.name))
        guard existing.contains(base) else { return base }
        var n = 2
        while existing.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    /// 保存済みプロファイルをロードする。未保存なら旧キーワードからマイグレーションする。
    private static func load(from defaults: UserDefaults)
        -> (profiles: [KeywordProfile], selectedID: UUID) {
        // 1) 既存プロファイル配列があればそれをロード。
        if let data = defaults.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([KeywordProfile].self, from: data),
           !decoded.isEmpty {
            let saved = defaults.string(forKey: selectedIDKey).flatMap(UUID.init(uuidString:))
            let selectedID = decoded.first { $0.id == saved }?.id ?? decoded[0].id
            return (decoded, selectedID)
        }

        // 2) 初回（プロファイル未保存）: 旧 contextKeywords を取り込む。
        let legacy = defaults.string(forKey: legacyKeywordsKey)
        let seed = (legacy?.isEmpty == false) ? legacy! : KeywordParser.defaultKeywords
        let initial = KeywordProfile(name: defaultProfileName, keywords: seed)
        return ([initial], initial.id)
    }
}
