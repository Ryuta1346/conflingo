import Foundation
import LocalAuthentication
import Security
import Synchronization
import Testing
@testable import ConfLingo

@Suite(.serialized, .timeLimit(.minutes(1)))
struct KeychainOperationsTests {
    @Test(arguments: [errSecSuccess, errSecItemNotFound])
    func failedRestorationCannotReturnSuccessfulRead(status: OSStatus) {
        let security = FakeKeychainSecurity()
        security.state.withLock {
            $0.copyStatus = status
            $0.setStatuses = [errSecSuccess, errSecAuthFailed]
        }
        let operations = KeychainOperations(security: security)

        #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "first") }
        #expect(security.events == ["get", "set:false", "read:first", "set:true"])
    }

    @Test(arguments: [true, false])
    func failedRestorationBlocksOtherConnectionsUntilRecovered(allowed: Bool) throws {
        let security = FakeKeychainSecurity()
        security.state.withLock {
            $0.allowed = allowed
            $0.setStatuses = [errSecSuccess, errSecAuthFailed, errSecAuthFailed, errSecAuthFailed, errSecAuthFailed]
        }
        let operations = KeychainOperations(security: security)
        #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "first") }
        #expect(throws: InsightFailure.keyStorage) { try operations.save("synthetic", service: "second") }
        #expect(throws: InsightFailure.keyStorage) { try operations.delete(service: "second") }
        #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "second") }
        #expect(security.events == ["get", "set:false", "read:first"] + Array(repeating: "set:\(allowed)", count: 4))

        try operations.save("synthetic", service: "second")
        #expect(security.events.suffix(2) == ["set:\(allowed)", "update:second"])
        #expect(security.state.withLock { $0.allowed } == allowed)
    }

    @Test(arguments: [true, false], ["read", "save", "delete"])
    func otherConnectionsWaitForReadRestoration(allowed: Bool, operation: String) throws {
        let gate = KeychainTestGate()
        let security = FakeKeychainSecurity { event in
            if event == "read:first" { gate.pause() }
        }
        security.state.withLock { $0.allowed = allowed }
        let operations = KeychainOperations(security: security)
        try assertSerialized(gate: gate, first: { _ = try operations.read(service: "first") }, second: {
            try perform(operation, on: operations, service: "second")
        })
        let following = operation == "read" ? ["get", "set:false", "read:second", "set:\(allowed)"]
            : [operation == "save" ? "update:second" : "delete:second"]
        #expect(security.events == ["get", "set:false", "read:first", "set:\(allowed)"] + following)
        #expect(security.state.withLock { $0.allowed } == allowed)
    }

    @Test(arguments: ["read", "save", "delete"])
    func missingItemUpdateAndAddStayTogether(operation: String) throws {
        let gate = KeychainTestGate()
        let security = FakeKeychainSecurity { event in
            if event == "update:first" { gate.pause() }
        }
        security.state.withLock { $0.updateStatus = errSecItemNotFound }
        let operations = KeychainOperations(security: security)
        try assertSerialized(gate: gate, first: { try operations.save("synthetic", service: "first") }, second: {
            try perform(operation, on: operations, service: "second")
        })
        let following: [String]
        switch operation {
        case "read": following = ["get", "set:false", "read:second", "set:true"]
        case "save": following = ["update:second", "add:second"]
        default: following = ["delete:second"]
        }
        #expect(security.events == ["update:first", "add:first"] + following)
    }

    @Test(arguments: [true, false], ["success", "missing", "error", "invalidType", "invalidUTF8", "nil"])
    func readOutcomesRestoreOriginalSetting(allowed: Bool, outcome: String) throws {
        let security = FakeKeychainSecurity()
        security.state.withLock {
            $0.allowed = allowed
            if outcome == "missing" { $0.copyStatus = errSecItemNotFound }
            if outcome == "error" { $0.copyStatus = errSecAuthFailed }
            if outcome == "invalidType" { $0.invalidResult = true }
            if outcome == "invalidUTF8" { $0.data = Data([0xFF]) }
            if outcome == "nil" { $0.missingResult = true }
        }
        let operations = KeychainOperations(security: security)
        if outcome == "success" { #expect(try operations.read(service: "first") == "synthetic") }
        else if outcome == "missing" { #expect(try operations.read(service: "first") == nil) }
        else { #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "first") } }
        #expect(security.events == ["get", "set:false", "read:first", "set:\(allowed)"])
        #expect(security.state.withLock { $0.allowed } == allowed)
    }

    @Test func failedSettingLookupDoesNotChangeSettingsOrReadItem() throws {
        let security = FakeKeychainSecurity()
        security.state.withLock { $0.getStatus = errSecAuthFailed }
        let operations = KeychainOperations(security: security)
        #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "first") }
        #expect(security.events == ["get"])
        security.state.withLock { $0.getStatus = errSecSuccess }
        #expect(try operations.read(service: "first") == "synthetic")
    }

    @Test(arguments: [true, false], [true, false])
    func failedDisableRestoresWithoutReading(allowed: Bool, restorationFails: Bool) throws {
        let security = FakeKeychainSecurity()
        security.state.withLock {
            $0.allowed = allowed
            $0.setStatuses = [errSecAuthFailed, restorationFails ? errSecAuthFailed : errSecSuccess]
        }
        let operations = KeychainOperations(security: security)
        #expect(throws: InsightFailure.keyStorage) { try operations.read(service: "first") }
        #expect(security.events == ["get", "set:false", "set:\(allowed)"])
        try operations.delete(service: "second")
        let following = restorationFails ? ["set:\(allowed)", "delete:second"] : ["delete:second"]
        #expect(security.events == ["get", "set:false", "set:\(allowed)"] + following)
        #expect(security.state.withLock { $0.allowed } == allowed)
    }

    @Test(arguments: ["update", "add", "delete"])
    func failedWriteReleasesOperationBoundary(operation: String) throws {
        let security = FakeKeychainSecurity()
        security.state.withLock {
            if operation == "update" { $0.updateStatus = errSecAuthFailed }
            if operation == "add" { $0.updateStatus = errSecItemNotFound; $0.addStatus = errSecAuthFailed }
            if operation == "delete" { $0.deleteStatus = errSecAuthFailed }
        }
        let operations = KeychainOperations(security: security)
        #expect(throws: InsightFailure.keyStorage) {
            try perform(operation == "delete" ? "delete" : "save", on: operations, service: "first")
        }
        let expected = operation == "add" ? ["update:first", "add:first"] : ["\(operation):first"]
        #expect(security.events == expected)
        #expect(try operations.read(service: "second") == "synthetic")
    }

    @Test(arguments: [errSecSuccess, errSecItemNotFound])
    func deletionIsIdempotent(status: OSStatus) throws {
        let security = FakeKeychainSecurity()
        security.state.withLock { $0.deleteStatus = status; $0.allowed = false }
        let operations = KeychainOperations(security: security)
        try operations.delete(service: "first")
        #expect(security.events == ["delete:first"])
        #expect(!security.state.withLock { $0.allowed })
    }

    @MainActor @Test func storesShareRecoveryAndReadOffMainThread() async throws {
        let security = FakeKeychainSecurity { event in
            if event == "read:first" { #expect(!Thread.isMainThread) }
        }
        security.state.withLock { $0.setStatuses = [errSecSuccess, errSecAuthFailed, errSecAuthFailed] }
        let operations = KeychainOperations(security: security)
        let first = KeychainAPIKeyStore(service: "first", operations: operations)
        let second = KeychainAPIKeyStore(service: "second", operations: operations)
        await #expect(throws: InsightFailure.keyStorage) { try await first.read() }
        #expect(throws: InsightFailure.keyStorage) { try second.save("synthetic") }
        try second.delete()
        #expect(security.events == ["get", "set:false", "read:first", "set:true", "set:true", "set:true", "delete:second"])
    }

    private func perform(_ operation: String, on operations: KeychainOperations, service: String) throws {
        switch operation {
        case "read": _ = try operations.read(service: service)
        case "save": try operations.save("synthetic", service: service)
        default: try operations.delete(service: service)
        }
    }

    private func assertSerialized(gate: KeychainTestGate, first: @escaping @Sendable () throws -> Void,
                                  second: @escaping @Sendable () throws -> Void) throws {
        let initial = DispatchGroup()
        initial.enter()
        Thread.detachNewThread {
            defer { initial.leave() }
            #expect(throws: Never.self) { try first() }
        }
        defer { gate.release.signal() }
        try #require(gate.entered.wait(timeout: .now() + 5) == .success)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            started.signal()
            defer { finished.signal() }
            #expect(throws: Never.self) { try second() }
        }
        try #require(started.wait(timeout: .now() + 5) == .success)
        let earlyFinish = finished.wait(timeout: .now() + 0.2)
        gate.release.signal()
        #expect(initial.wait(timeout: .now() + 5) == .success)
        if earlyFinish == .timedOut { #expect(finished.wait(timeout: .now() + 5) == .success) }
        #expect(earlyFinish == .timedOut)
    }
}

final class KeychainTestGate: Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    func pause() {
        entered.signal()
        #expect(release.wait(timeout: .now() + 5) == .success)
    }
}

final class FakeKeychainSecurity: KeychainSecurity, Sendable {
    struct State {
        var allowed = true
        var getStatus = errSecSuccess
        var setStatuses: [OSStatus] = []
        var copyStatus = errSecSuccess
        var data = Data("synthetic".utf8)
        var invalidResult = false
        var missingResult = false
        var updateStatus = errSecSuccess
        var addStatus = errSecSuccess
        var deleteStatus = errSecSuccess
        var events: [String] = []
    }
    let state = Mutex(State())
    let onEvent: @Sendable (String) -> Void
    init(onEvent: @escaping @Sendable (String) -> Void = { _ in }) { self.onEvent = onEvent }
    var events: [String] { state.withLock { $0.events } }

    private func record(_ event: String) {
        state.withLock { $0.events.append(event) }
        onEvent(event)
    }

    func interactionAllowed() -> (OSStatus, Bool) {
        record("get")
        return state.withLock { ($0.getStatus, $0.allowed) }
    }

    func setInteractionAllowed(_ allowed: Bool) -> OSStatus {
        record("set:\(allowed)")
        return state.withLock {
            let status = $0.setStatuses.isEmpty ? errSecSuccess : $0.setStatuses.removeFirst()
            if status == errSecSuccess { $0.allowed = allowed }
            return status
        }
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        checkQuery(query)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        record("read:\(query[kSecAttrService as String] as? String ?? "")")
        let snapshot = state.withLock { ($0.copyStatus, $0.data, $0.invalidResult, $0.missingResult) }
        if snapshot.3 { return (snapshot.0, nil) }
        return (snapshot.0, snapshot.2 ? "invalid" as CFString : snapshot.1 as CFData)
    }

    func update(_ query: [String: Any], values: [String: Any]) -> OSStatus {
        checkQuery(query)
        #expect(values[kSecValueData as String] as? Data == Data("synthetic".utf8))
        record("update:\(query[kSecAttrService as String] as? String ?? "")")
        return state.withLock { $0.updateStatus }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        checkQuery(attributes)
        #expect(attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecValueData as String] as? Data == Data("synthetic".utf8))
        record("add:\(attributes[kSecAttrService as String] as? String ?? "")")
        return state.withLock { $0.addStatus }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        checkQuery(query)
        record("delete:\(query[kSecAttrService as String] as? String ?? "")")
        return state.withLock { $0.deleteStatus }
    }

    private func checkQuery(_ query: [String: Any]) {
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrAccount as String] as? String == "user-api-key")
        #expect((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
        #expect(query[kSecUseDataProtectionKeychain as String] == nil)
    }
}
