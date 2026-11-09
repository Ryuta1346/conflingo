import Foundation
import LocalAuthentication
import Observation
import Security

@MainActor
protocol APIKeyStore {
    func read() async throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

@MainActor
struct KeychainAPIKeyStore: APIKeyStore {
    var service = "com.gavrri.conflingo.gemini-api"
    private nonisolated static let readLock = NSLock()
    private var query: [String: Any] { Self.query(service: service) }

    private nonisolated static func query(service: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "user-api-key", kSecUseAuthenticationContext as String: context]
    }

    func read() async throws -> String? {
        let service = service
        return try await Task.detached { try Self.readSynchronously(service: service) }.value
    }

    private nonisolated static func readSynchronously(service: String) throws -> String? {
        // Existing file-based Keychain items ignore LAContext's UI prohibition.
        readLock.lock()
        defer { readLock.unlock() }
        var interactionAllowed: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&interactionAllowed) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { throw InsightFailure.keyStorage }
        defer { SecKeychainSetUserInteractionAllowed(interactionAllowed.boolValue) }
        var attributes = query(service: service)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw InsightFailure.keyStorage }
        return key
    }

    func save(_ key: String) throws {
        let values = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw InsightFailure.keyStorage }
        var attributes = query
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrSynchronizable as String] = false
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw InsightFailure.keyStorage }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw InsightFailure.keyStorage }
    }
}

@MainActor
@Observable
final class GeminiCredentials {
    private(set) var configured = false
    private(set) var message = ""
    private var checking = false
    private var readFailed = false
    private var refreshVersion = 0
    let store: any APIKeyStore
    var onChange: (() -> Void)?

    init(store: any APIKeyStore = KeychainAPIKeyStore()) { self.store = store }

    var statusText: String {
        if checking { return "APIキーを確認しています…" }
        if readFailed { return "APIキーの登録状態を確認できません" }
        return configured ? "APIキー登録済み" : "APIキー未登録"
    }

    func refresh() async {
        refreshVersion += 1
        let version = refreshVersion
        checking = true
        message = ""
        defer { if refreshVersion == version { checking = false } }
        do {
            let exists = try await store.read() != nil
            guard refreshVersion == version, !Task.isCancelled else { return }
            configured = exists
            readFailed = false
        } catch {
            guard refreshVersion == version, !Task.isCancelled else { return }
            configured = false
            readFailed = true
            message = InsightFailure.keyStorage.localizedDescription
        }
    }

    func save(_ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 512, key.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) }) else {
            message = "有効なAPIキーを入力してください。"
            return
        }
        onChange?()
        do {
            try store.save(key)
            refreshVersion += 1
            checking = false
            configured = true
            readFailed = false
            message = "APIキーをKeychainへ保存しました。"
        } catch { message = InsightFailure.keyStorage.localizedDescription }
    }

    func delete() {
        onChange?()
        do {
            try store.delete()
            refreshVersion += 1
            checking = false
            configured = false
            readFailed = false
            message = "APIキーを削除しました。"
        } catch { message = InsightFailure.keyStorage.localizedDescription }
    }
}
