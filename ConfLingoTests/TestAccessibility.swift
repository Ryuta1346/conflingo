import AppKit

@MainActor
final class TestAccessibility {
    static let shared = TestAccessibility(
        read: { NSApp.accessibilityAttributeValue(NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) },
        write: { NSApp.accessibilitySetValue($0, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")) })

    private var users = 0
    private var previous: Any?
    private let read: () -> Any?
    private let write: (Any) -> Void

    init(read: @escaping () -> Any?, write: @escaping (Any) -> Void) {
        self.read = read
        self.write = write
    }

    func enable() -> () -> Void {
        if users == 0 {
            previous = read()
            write(true)
        }
        users += 1
        var released = false
        return {
            guard !released else { return }
            released = true
            self.users -= 1
            if self.users == 0 {
                self.write(self.previous ?? false)
                self.previous = nil
            }
        }
    }
}

@MainActor
func waitForTestCondition(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(20))
    }
    return true
}
