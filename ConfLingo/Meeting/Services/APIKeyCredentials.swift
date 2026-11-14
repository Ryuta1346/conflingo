import Foundation
import Observation

@MainActor
protocol APIKeyStore {
    func read() async throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

@MainActor
struct KeychainAPIKeyStore: APIKeyStore {
    var service: String
    private let operations: KeychainOperations

    init(service: String = "com.gavrri.conflingo.gemini-api", operations: KeychainOperations = .shared) {
        self.service = service
        self.operations = operations
    }

    func read() async throws -> String? {
        let service = service
        let operations = operations
        return try await Task.detached { try operations.read(service: service) }.value
    }

    func save(_ key: String) throws { try operations.save(key, service: service) }
    func delete() throws { try operations.delete(service: service) }
}

@MainActor
@Observable
final class APIKeyCredentials {
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

    static func isValid(_ key: String) -> Bool {
        !key.isEmpty && key.count <= 512 && key.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })
    }

    @discardableResult
    func save(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValid(key) else {
            message = "有効なAPIキーを入力してください。"
            return false
        }
        onChange?()
        do {
            try store.save(key)
            refreshVersion += 1
            checking = false
            configured = true
            readFailed = false
            message = "APIキーをKeychainへ保存しました。"
            return true
        } catch { message = InsightFailure.keyStorage.localizedDescription; return false }
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
