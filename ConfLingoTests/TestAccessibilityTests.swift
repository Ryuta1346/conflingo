import Testing

@MainActor
struct TestAccessibilityTests {
    @Test(arguments: [false, true], [false, true])
    func overlappingSuitesKeepAccessibilityEnabledUntilLastRelease(initial: Bool, releaseFirst: Bool) {
        var enabled = initial
        let scope = TestAccessibility(read: { enabled }, write: { enabled = $0 as? Bool ?? false })
        let first = scope.enable()
        let second = scope.enable()
        #expect(enabled)
        if releaseFirst { first() } else { second() }
        #expect(enabled)
        if releaseFirst { second() } else { first() }
        #expect(enabled == initial)
    }

    @Test func waitForUnreachedConditionHasFiniteDeadline() async throws {
        #expect(try await !waitForTestCondition(timeout: .milliseconds(20)) { false })
        #expect(try await waitForTestCondition { true })
    }
}
