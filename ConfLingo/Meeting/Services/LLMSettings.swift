import Foundation
import Observation

@MainActor
@Observable
final class LLMSettings {
    static let storageKey = "llmConnections.v1"
    private(set) var connections: [LLMConnection]
    private(set) var selectedID: UUID
    private(set) var revision = 0
    private let defaults: UserDefaults
    private let keyStore: (String) -> any APIKeyStore
    @ObservationIgnored private var credentialCache: [UUID: APIKeyCredentials] = [:]
    let changes = EventSignal<Void>()

    var selected: LLMConnection { connections.first { $0.id == selectedID } ?? connections[0] }
    var credentials: APIKeyCredentials { credentials(for: selected) }

    init(defaults: UserDefaults = .standard, legacyCredentials: APIKeyCredentials? = nil,
         keyStore: @escaping (String) -> any APIKeyStore = { KeychainAPIKeyStore(service: $0) }) {
        self.defaults = defaults
        self.keyStore = keyStore
        if let data = defaults.data(forKey: Self.storageKey), let saved = try? JSONDecoder().decode(Saved.self, from: data),
           !saved.connections.isEmpty, Set(saved.connections.map(\.id)).count == saved.connections.count,
           saved.connections.contains(where: { $0.id == saved.selectedID }) {
            connections = saved.connections
            selectedID = saved.selectedID
        } else {
            connections = [.legacyGemini]
            selectedID = LLMConnection.legacyGeminiID
        }
        if let legacyCredentials {
            credentialCache[LLMConnection.legacyGeminiID] = legacyCredentials
            legacyCredentials.onChange = { [weak self] in self?.changed() }
        }
    }

    func credentials(for connection: LLMConnection) -> APIKeyCredentials {
        if let cached = credentialCache[connection.id] { return cached }
        let result = APIKeyCredentials(store: keyStore(connection.keychainService))
        result.onChange = { [weak self] in self?.changed() }
        credentialCache[connection.id] = result
        return result
    }

    func select(_ id: UUID) {
        guard selectedID != id, connections.contains(where: { $0.id == id }) else { return }
        changed()
        selectedID = id
        persist()
    }

    func save(_ connection: LLMConnection) throws {
        try connection.validate()
        if let old = connections.first(where: { $0.id == connection.id }) {
            guard old.provider == connection.provider else { throw InsightFailure.invalidConfiguration }
            if old.baseURL != connection.baseURL {
                // Clear before committing the new destination; a Keychain failure leaves the old configuration intact.
                try credentials(for: old).store.delete()
                credentialCache.removeValue(forKey: old.id)
            }
            if old == connection, selectedID == connection.id { return }
        }
        changed()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) { connections[index] = connection }
        else { connections.append(connection) }
        selectedID = connection.id
        persist()
    }

    func delete(_ id: UUID) throws {
        guard connections.count > 1, let connection = connections.first(where: { $0.id == id }) else { return }
        try credentials(for: connection).store.delete()
        changed()
        connections.removeAll { $0.id == id }
        credentialCache.removeValue(forKey: id)
        if selectedID == id { selectedID = connections[0].id }
        persist()
    }

    private func changed() { revision += 1; changes.emit(()) }
    private func persist() {
        guard let data = try? JSONEncoder().encode(Saved(connections: connections, selectedID: selectedID)) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
    private struct Saved: Codable {
        let connections: [LLMConnection]
        let selectedID: UUID
    }
}
