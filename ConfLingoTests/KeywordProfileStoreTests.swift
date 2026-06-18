import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KeywordProfileStoreTests {
    /// 各テストで副作用を隔離するための分離 UserDefaults。
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    // MARK: - マイグレーション

    @Test func migratesLegacyKeywords() {
        let defaults = makeDefaults()
        defaults.set("Foo, Bar=バー", forKey: KeywordProfileStore.legacyKeywordsKey)

        let store = KeywordProfileStore(defaults: defaults)

        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == KeywordProfileStore.defaultProfileName)
        #expect(store.profiles[0].keywords == "Foo, Bar=バー")
        #expect(store.selectedID == store.profiles[0].id)
    }

    @Test func seedsDefaultKeywordsWhenNoLegacy() {
        let store = KeywordProfileStore(defaults: makeDefaults())

        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == KeywordProfileStore.defaultProfileName)
        #expect(store.profiles[0].keywords == KeywordParser.defaultKeywords)
    }

    @Test func emptyLegacyKeywordsFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("", forKey: KeywordProfileStore.legacyKeywordsKey)

        let store = KeywordProfileStore(defaults: defaults)

        #expect(store.profiles[0].keywords == KeywordParser.defaultKeywords)
    }

    // MARK: - 永続化往復

    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults()
        let storeA = KeywordProfileStore(defaults: defaults)
        let added = storeA.addProfile(name: "会議A", keywords: "term1")

        let storeB = KeywordProfileStore(defaults: defaults)

        #expect(storeB.profiles == storeA.profiles)
        #expect(storeB.selectedID == added.id)
        #expect(storeB.selectedProfile.name == "会議A")
    }

    @Test func updateSelectedKeywordsPersists() {
        let defaults = makeDefaults()
        let storeA = KeywordProfileStore(defaults: defaults)
        storeA.updateSelectedKeywords("更新後のキーワード")

        let storeB = KeywordProfileStore(defaults: defaults)
        #expect(storeB.selectedProfile.keywords == "更新後のキーワード")
    }

    // MARK: - CRUD: add

    @Test func addProfileAppendsAndSelects() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let before = store.profiles.count
        let added = store.addProfile(name: "新しい辞書")

        #expect(store.profiles.count == before + 1)
        #expect(store.selectedID == added.id)
        #expect(store.selectedProfile.keywords == "")
    }

    @Test func addProfileDeduplicatesName() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        store.addProfile(name: "同名")
        let second = store.addProfile(name: "同名")

        #expect(second.name == "同名 2")
    }

    // MARK: - CRUD: duplicate

    @Test func duplicateCopiesKeywordsWithNewID() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let source = store.addProfile(name: "元", keywords: "A, B")
        let copy = store.duplicate(source.id)

        #expect(copy != nil)
        #expect(copy?.id != source.id)
        #expect(copy?.keywords == "A, B")
        #expect(copy?.name == "元 のコピー")
        #expect(store.selectedID == copy?.id)
    }

    @Test func duplicateUnknownIDReturnsNil() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        #expect(store.duplicate(UUID()) == nil)
    }

    // MARK: - CRUD: rename

    @Test func renameChangesNameOnly() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let p = store.addProfile(name: "旧名", keywords: "kw")
        store.rename(p.id, to: "新名")

        let renamed = store.profiles.first { $0.id == p.id }
        #expect(renamed?.name == "新名")
        #expect(renamed?.keywords == "kw")
    }

    @Test func renameIgnoresBlankName() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let p = store.addProfile(name: "保持", keywords: "")
        store.rename(p.id, to: "   ")

        #expect(store.profiles.first { $0.id == p.id }?.name == "保持")
    }

    // MARK: - CRUD: delete

    @Test func deleteSelectedMovesSelection() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let first = store.selectedProfile
        let second = store.addProfile(name: "二番目") // 選択は second に移っている

        let ok = store.delete(second.id)

        #expect(ok)
        #expect(store.profiles.count == 1)
        #expect(store.selectedID == first.id) // 隣（先頭）へフォールバック
        #expect(store.profiles.contains { $0.id == store.selectedID })
    }

    @Test func deleteLastProfileFails() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let only = store.selectedProfile

        let ok = store.delete(only.id)

        #expect(!ok)
        #expect(store.profiles.count == 1)
    }

    @Test func deleteNonSelectedKeepsSelection() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let first = store.selectedProfile
        let second = store.addProfile(name: "消す対象")
        store.select(first.id)

        let ok = store.delete(second.id)

        #expect(ok)
        #expect(store.selectedID == first.id)
    }

    // MARK: - select

    @Test func selectChangesSelectedProfile() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let first = store.selectedProfile
        let second = store.addProfile(name: "B")
        store.select(first.id)
        #expect(store.selectedProfile.id == first.id)
        store.select(second.id)
        #expect(store.selectedProfile.id == second.id)
    }

    @Test func selectUnknownIDIsIgnored() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let current = store.selectedID
        store.select(UUID())
        #expect(store.selectedID == current)
    }

    // MARK: - フォールバック

    @Test func corruptedSelectedIDFallsBackToFirst() {
        let defaults = makeDefaults()
        // 正常なプロファイルを保存してから selectedID を壊す。
        _ = KeywordProfileStore(defaults: defaults)
        defaults.set("not-a-uuid", forKey: KeywordProfileStore.selectedIDKey)

        let store = KeywordProfileStore(defaults: defaults)
        #expect(store.selectedID == store.profiles[0].id)
    }

    @Test func unknownSelectedIDFallsBackToFirst() {
        let defaults = makeDefaults()
        _ = KeywordProfileStore(defaults: defaults)
        defaults.set(UUID().uuidString, forKey: KeywordProfileStore.selectedIDKey)

        let store = KeywordProfileStore(defaults: defaults)
        #expect(store.selectedID == store.profiles[0].id)
    }

    /// 破損した profiles JSON はデコード失敗としてフォールバックし、旧キーワードを取り込む。
    @Test func corruptedProfilesJSONFallsBackToLegacy() {
        let defaults = makeDefaults()
        defaults.set(Data("not valid json".utf8), forKey: KeywordProfileStore.profilesKey)
        defaults.set("Legacy, Keywords", forKey: KeywordProfileStore.legacyKeywordsKey)

        let store = KeywordProfileStore(defaults: defaults)

        #expect(store.profiles.count == 1)
        #expect(store.profiles[0].name == KeywordProfileStore.defaultProfileName)
        #expect(store.profiles[0].keywords == "Legacy, Keywords")
    }

    // MARK: - delete 境界

    /// 中途位置の選択中プロファイルを削除すると、同インデックス（=次の要素）へ選択が移る。
    @Test func deleteMiddleProfileSelectsNext() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let first = store.selectedProfile
        let second = store.addProfile(name: "B")
        store.select(first.id)
        let third = store.addProfile(name: "C") // profiles = [first, second, third]
        store.select(second.id)                 // 中途位置(index 1)を選択

        let ok = store.delete(second.id)

        #expect(ok)
        #expect(store.profiles.count == 2)
        #expect(store.selectedID == third.id) // min(1, 1) → 次の要素 third
        #expect(!store.profiles.contains { $0.id == second.id })
    }

    // MARK: - rename / uniqueName / update のエッジ

    @Test func renameUnknownIDIsIgnored() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        _ = store.addProfile(name: "元", keywords: "kw")
        let before = store.profiles

        store.rename(UUID(), to: "新名")

        #expect(store.profiles == before)
    }

    /// 同名が複数層（base, base 2, base 3 …）存在しても連番が衝突しない。
    @Test func uniqueNameHandlesMultipleLevelsOfCollision() {
        let store = KeywordProfileStore(defaults: makeDefaults())
        let p1 = store.addProfile(name: "テスト")
        let p2 = store.addProfile(name: "テスト")
        let p3 = store.addProfile(name: "テスト")
        let p4 = store.addProfile(name: "テスト")

        #expect(p1.name == "テスト")
        #expect(p2.name == "テスト 2")
        #expect(p3.name == "テスト 3")
        #expect(p4.name == "テスト 4")
    }

    /// 同一内容での更新は no-op（値は保持され往復しても一致する）。
    @Test func updateSelectedKeywordsWithSameValueIsNoOp() {
        let defaults = makeDefaults()
        let store = KeywordProfileStore(defaults: defaults)
        store.updateSelectedKeywords("A, B")
        store.updateSelectedKeywords("A, B") // 同一内容 → 再永続化なし

        let reloaded = KeywordProfileStore(defaults: defaults)
        #expect(reloaded.selectedProfile.keywords == "A, B")
    }
}
