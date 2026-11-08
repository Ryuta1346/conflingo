import Foundation
import LocalAuthentication
import Observation
import Security

@MainActor
protocol APIKeyStore {
    func read() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

@MainActor
struct KeychainAPIKeyStore: APIKeyStore {
    var service = "com.gavrri.conflingo.gemini-api"
    private var query: [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "user-api-key", kSecUseAuthenticationContext as String: context]
    }

    func read() throws -> String? {
        var attributes = query
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
    let store: any APIKeyStore
    var onChange: (() -> Void)?

    init(store: any APIKeyStore = KeychainAPIKeyStore()) { self.store = store }

    func refresh() {
        do { configured = try store.read() != nil }
        catch { message = InsightFailure.keyStorage.localizedDescription }
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
            configured = true
            message = "APIキーをKeychainへ保存しました。"
        } catch { message = InsightFailure.keyStorage.localizedDescription }
    }

    func delete() {
        onChange?()
        do {
            try store.delete()
            configured = false
            message = "APIキーを削除しました。"
        } catch { message = InsightFailure.keyStorage.localizedDescription }
    }
}
