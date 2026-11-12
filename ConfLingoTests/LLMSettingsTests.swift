import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct LLMSettingsTests {
    @Test func connectionsPersistWithoutKeysAndUseSeparateStores() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let keys = TestConnectionKeys()
        let settings = LLMSettings(defaults: defaults, keyStore: keys.store)
        #expect(settings.selected.provider == .gemini)
        #expect(settings.selected.keychainService == "com.gavrri.conflingo.gemini-api")
        var first = LLMConnection.preset(.custom)
        first.model = "model-a"
        first.baseURL = "https://first.example/v1"
        try settings.save(first)
        settings.credentials.save("first-secret")
        var second = LLMConnection.preset(.custom)
        second.model = "model-b"
        second.baseURL = "https://second.example/prefix/v1/"
        try settings.save(second)
        settings.credentials.save("second-secret")
        settings.select(first.id)
        #expect(try await settings.credentials.store.read() == "first-secret")
        let restored = LLMSettings(defaults: defaults, keyStore: keys.store)
        #expect(restored.selected == first)
        #expect(restored.connections.count == 3)
        let saved = try #require(defaults.data(forKey: LLMSettings.storageKey))
        #expect(!String(decoding: saved, as: UTF8.self).contains("secret"))
        #expect(try second.endpoint("chat/completions").absoluteString == "https://second.example/prefix/v1/chat/completions")
    }

    @Test func endpointChangeDoesNotForwardPreviousKeyAndRevokesPermission() async throws {
        let keys = TestConnectionKeys()
        let settings = LLMSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!, keyStore: keys.store)
        var connection = LLMConnection.preset(.custom)
        connection.baseURL = "https://one.example/v1"
        connection.model = "model"
        try settings.save(connection)
        settings.credentials.save("private-key")
        var changes = 0
        settings.onChange = { changes += 1 }
        connection.baseURL = "https://two.example/v1"
        try settings.save(connection)
        #expect(try await settings.credentials.store.read() == nil)
        #expect(changes == 1)
        settings.select(LLMConnection.legacyGeminiID)
        #expect(changes == 2)
    }

    @Test(arguments: ["http://cloud.example/v1", "https://user:pass@host/v1", "https://host/v1?key=secret", "https://host/v1#fragment", "file:///tmp/model"])
    func unsafeCloudEndpointsAreRejected(url: String) {
        var connection = LLMConnection.preset(.custom)
        connection.baseURL = url
        #expect(throws: InsightFailure.invalidEndpoint) { try connection.endpoint("models") }
    }

    @Test(arguments: ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:1234/v1"])
    func localHTTPAcceptsLoopbackOnly(url: String) throws {
        var connection = LLMConnection.preset(.local)
        connection.baseURL = url
        #expect(try connection.endpoint("models").scheme == "http")
        connection.baseURL = "http://192.168.1.10:1234/v1"
        #expect(throws: InsightFailure.invalidEndpoint) { try connection.endpoint("models") }
    }
}

@MainActor
final class TestConnectionKeys {
    var stores: [String: MemoryAPIKeyStore] = [:]
    func store(_ service: String) -> any APIKeyStore {
        if let store = stores[service] { return store }
        let store = MemoryAPIKeyStore()
        stores[service] = store
        return store
    }
}
