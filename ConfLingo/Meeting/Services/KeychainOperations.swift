import Foundation
import LocalAuthentication
import Security
import Synchronization

protocol KeychainSecurity: Sendable {
    func interactionAllowed() -> (OSStatus, Bool)
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemKeychainSecurity: KeychainSecurity {
    func interactionAllowed() -> (OSStatus, Bool) {
        var allowed: DarwinBoolean = false
        let status = SecKeychainGetUserInteractionAllowed(&allowed)
        return (status, allowed.boolValue)
    }
    func setInteractionAllowed(_ allowed: Bool) -> OSStatus { SecKeychainSetUserInteractionAllowed(allowed) }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }
    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, values as CFDictionary)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

final class KeychainOperations: Sendable {
    static let shared = KeychainOperations(security: SystemKeychainSecurity())
    private let security: any KeychainSecurity
    // Every production store shares this boundary because the legacy UI setting is process-wide.
    private let pendingRestoration = Mutex<Bool?>(nil)

    init(security: any KeychainSecurity) { self.security = security }

    private func query(service: String) -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: "user-api-key", kSecUseAuthenticationContext as String: context]
    }

    func read(service: String) throws -> String? {
        try pendingRestoration.withLock { pending in
            try restore(&pending)
            let (status, allowed) = security.interactionAllowed()
            guard status == errSecSuccess else { throw InsightFailure.keyStorage }
            pending = allowed
            // Existing file-based items can ignore LAContext's UI prohibition.
            guard security.setInteractionAllowed(false) == errSecSuccess else {
                try restore(&pending)
                throw InsightFailure.keyStorage
            }
            var attributes = query(service: service)
            attributes[kSecReturnData as String] = true
            attributes[kSecMatchLimit as String] = kSecMatchLimitOne
            let (readStatus, result) = security.copyMatching(attributes)
            try restore(&pending)
            if readStatus == errSecItemNotFound { return nil }
            guard readStatus == errSecSuccess, let data = result as? Data,
                  let key = String(data: data, encoding: .utf8) else { throw InsightFailure.keyStorage }
            return key
        }
    }

    func save(_ key: String, service: String) throws {
        try pendingRestoration.withLock { pending in
            try restore(&pending)
            let values = [kSecValueData as String: Data(key.utf8)]
            let status = security.update(query(service: service), values: values)
            if status == errSecSuccess { return }
            guard status == errSecItemNotFound else { throw InsightFailure.keyStorage }
            var attributes = query(service: service)
            attributes[kSecValueData as String] = Data(key.utf8)
            attributes[kSecAttrSynchronizable as String] = false
            guard security.add(attributes) == errSecSuccess else { throw InsightFailure.keyStorage }
        }
    }

    func delete(service: String) throws {
        try pendingRestoration.withLock { pending in
            try restore(&pending)
            let status = security.delete(query(service: service))
            guard status == errSecSuccess || status == errSecItemNotFound else { throw InsightFailure.keyStorage }
        }
    }

    private func restore(_ pending: inout Bool?) throws {
        guard let allowed = pending else { return }
        guard security.setInteractionAllowed(allowed) == errSecSuccess else { throw InsightFailure.keyStorage }
        pending = nil
    }
}
