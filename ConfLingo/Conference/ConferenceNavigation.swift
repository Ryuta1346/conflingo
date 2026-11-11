import Observation

@MainActor
@Observable
final class ConferenceNavigation {
    enum Destination: String, CaseIterable, Identifiable {
        case home, setup, live, settings, meeting, sessions
        var id: Self { self }
    }

    private(set) var destination: Destination
    var showsStopConfirmation = false
    private var pendingDestination: Destination?
    private(set) var isTransitioning = false

    init(destination: Destination = .home) {
        self.destination = destination
    }

    func request(_ target: Destination, phase: SessionPhase, forceConfirmation: Bool = false) {
        guard !isTransitioning, target != destination || forceConfirmation else { return }
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

    func requestMeetingExpansion(conferencePhase: SessionPhase) -> Bool {
        request(.meeting, phase: conferencePhase)
        return destination == .meeting && !isTransitioning
    }

    func confirmNavigation(store: SessionStore, stop: () async -> Void) async {
        await confirmNavigation(phase: { store.phase }, stop: stop)
    }

    func confirmNavigation(phase: () -> SessionPhase, stop: () async -> Void) async {
        guard !isTransitioning, let target = pendingDestination else { return }
        showsStopConfirmation = false
        isTransitioning = true
        defer {
            isTransitioning = false
            pendingDestination = nil
        }
        if phase() == .listening { await stop() }
        guard phase() == .idle else { return }
        destination = target
    }
}
