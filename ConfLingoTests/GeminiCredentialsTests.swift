import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct GeminiCredentialsTests {
    @Test func failedRefreshDoesNotReportAnUnregisteredKey() async {
        let store = MemoryAPIKeyStore()
        let settings = GeminiCredentials(store: store)
        settings.save("synthetic-key")
        store.fail = true
        await settings.refresh()
        #expect(!settings.configured)
        #expect(settings.statusText == "APIキーの登録状態を確認できません")
        store.fail = false
        await settings.refresh()
        #expect(settings.statusText == "APIキー登録済み")
        #expect(settings.message.isEmpty)
    }

    @Test func oldRefreshCannotOverwriteACompletedSave() async {
        let store = DeferredReadAPIKeyStore()
        let settings = GeminiCredentials(store: store)
        let refresh = Task { await settings.refresh() }
        await store.gate.entered.next()
        #expect(settings.statusText == "APIキーを確認しています…")
        settings.save("synthetic-key")
        store.gate.release()
        await refresh.value
        #expect(settings.configured)
        #expect(settings.statusText == "APIキー登録済み")
    }

    @Test(arguments: [true, false])
    func failedSaveKeepsPendingRegistrationCheck(hasExistingKey: Bool) async {
        let store = DeferredReadAPIKeyStore()
        store.value = hasExistingKey ? "existing-key" : nil
        store.failWrites = true
        let settings = GeminiCredentials(store: store)
        let refresh = Task { await settings.refresh() }
        await store.gate.entered.next()

        settings.save("replacement-key")
        #expect(settings.statusText == "APIキーを確認しています…")
        #expect(settings.message == InsightFailure.keyStorage.localizedDescription)
        store.gate.release()
        await refresh.value

        #expect(settings.configured == hasExistingKey)
        #expect(settings.statusText == (hasExistingKey ? "APIキー登録済み" : "APIキー未登録"))
        #expect(settings.message == InsightFailure.keyStorage.localizedDescription)
    }

    @Test func failedDeleteKeepsPendingRegistrationCheck() async {
        let store = DeferredReadAPIKeyStore()
        let settings = GeminiCredentials(store: store)
        settings.save("existing-key")
        store.failWrites = true
        let refresh = Task { await settings.refresh() }
        await store.gate.entered.next()

        settings.delete()
        #expect(settings.statusText == "APIキーを確認しています…")
        store.gate.release()
        await refresh.value

        #expect(settings.configured)
        #expect(settings.statusText == "APIキー登録済み")
        #expect(settings.message == InsightFailure.keyStorage.localizedDescription)
    }

    @Test func oldRefreshCannotOverwriteACompletedDelete() async {
        let store = DeferredReadAPIKeyStore()
        let settings = GeminiCredentials(store: store)
        settings.save("existing-key")
        let refresh = Task { await settings.refresh() }
        await store.gate.entered.next()

        settings.delete()
        store.gate.release()
        await refresh.value

        #expect(!settings.configured)
        #expect(settings.statusText == "APIキー未登録")
        #expect(settings.message == "APIキーを削除しました。")
    }

    @Test func registrationReplacementDeletionAndFailureAreTruthful() throws {
        let store = MemoryAPIKeyStore()
        let settings = GeminiCredentials(store: store)
        var changes = 0
        settings.onChange = { changes += 1 }
        settings.save(" test-key ")
        #expect(settings.configured)
        #expect(try store.read() == "test-key")
        settings.save("replacement")
        #expect(try store.read() == "replacement")
        settings.delete()
        #expect(!settings.configured)
        #expect(try store.read() == nil)
        #expect(changes == 3)
        store.fail = true
        settings.save("another")
        #expect(!settings.configured)
        #expect(settings.message.contains("できません"))
    }

    @Test func keychainRoundtripUsesUniqueTestItem() async throws {
        let store = KeychainAPIKeyStore(service: "com.gavrri.conflingo.tests.\(UUID())")
        defer { try? store.delete() }
        #expect(try await store.read() == nil)
        try store.save("synthetic-test-key")
        #expect(try await store.read() == "synthetic-test-key")
        try store.save("replacement-test-key")
        #expect(try await store.read() == "replacement-test-key")
        try store.delete()
        #expect(try await store.read() == nil)
    }
}

@MainActor
private final class DeferredReadAPIKeyStore: APIKeyStore {
    let gate = TestGate()
    var value: String?
    var failWrites = false
    func read() async throws -> String? {
        let snapshot = value
        await gate.wait()
        return snapshot
    }
    func save(_ key: String) throws {
        if failWrites { throw InsightFailure.keyStorage }
        value = key
    }
    func delete() throws {
        if failWrites { throw InsightFailure.keyStorage }
        value = nil
    }
}

@MainActor
final class MemoryAPIKeyStore: APIKeyStore {
    var value: String?
    var fail = false
    func read() throws -> String? { if fail { throw InsightFailure.keyStorage }; return value }
    func save(_ key: String) throws { if fail { throw InsightFailure.keyStorage }; value = key }
    func delete() throws { if fail { throw InsightFailure.keyStorage }; value = nil }
}
