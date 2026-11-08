import Foundation

@MainActor
final class MeetingTimeline {
    private(set) var sessionID = UUID()
    private let now: () -> TimeInterval
    private var startedAt: TimeInterval?

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    var offset: TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, now() - startedAt)
    }

    func beginInput() -> TimeInterval {
        if startedAt == nil { startedAt = now() }
        return offset
    }

    func reset() {
        sessionID = UUID()
        startedAt = nil
    }
}
