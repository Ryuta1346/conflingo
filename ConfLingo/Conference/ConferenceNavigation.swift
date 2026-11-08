import Observation

@MainActor
@Observable
final class ConferenceNavigation {
    enum Destination: String, CaseIterable, Identifiable {
        case home, setup, live, settings
        var id: Self { self }
    }

    private(set) var destination: Destination
    var showsStopConfirmation = false
    private var pendingDestination: Destination?
    private(set) var isTransitioning = false

    init(destination: Destination = .home) {
        self.destination = destination
    }

    func request(_ target: Destination, phase: SessionPhase) {
        guard !isTransitioning, target != destination else { return }
        switch phase {
        case .idle:
            destination = target
        case .listening:
            pendingDestination = target
            showsStopConfirmation = true
        case .preparing, .stopping:
            break
        }
    }

    func cancelNavigation() {
        showsStopConfirmation = false
        pendingDestination = nil
    }

    func confirmNavigation(store: SessionStore, stop: () async -> Void) async {
        guard !isTransitioning, let target = pendingDestination else { return }
        showsStopConfirmation = false
        isTransitioning = true
        defer {
            isTransitioning = false
            pendingDestination = nil
        }
        if store.phase == .listening { await stop() }
        guard store.phase == .idle else { return }
        destination = target
    }
}
