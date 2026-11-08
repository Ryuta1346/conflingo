import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct GeminiCredentialsTests {
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

    @Test func keychainRoundtripUsesUniqueTestItem() throws {
        let store = KeychainAPIKeyStore(service: "com.gavrri.conflingo.tests.\(UUID())")
        defer { try? store.delete() }
        #expect(try store.read() == nil)
        try store.save("synthetic-test-key")
        #expect(try store.read() == "synthetic-test-key")
        try store.save("replacement-test-key")
        #expect(try store.read() == "replacement-test-key")
        try store.delete()
        #expect(try store.read() == nil)
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
