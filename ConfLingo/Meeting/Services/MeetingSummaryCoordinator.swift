import Foundation
import Observation

@MainActor
@Observable
final class MeetingSummaryCoordinator {
    enum State: Equatable { case idle, sending, complete, interrupted, failed(InsightFailure) }
    private(set) var state: State = .idle
    private(set) var completed: MeetingSummary?
    private(set) var draft: [MeetingSummarySection] = []
    private(set) var partialText = ""
    private(set) var totalSections = 0
    private let store: MeetingSessionStore
    private let client: any InsightClient
    private let timeout: Duration
    private var operationID: UUID?
    private var requestID: UUID?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?

    init(store: MeetingSessionStore, client: any InsightClient, timeout: Duration = .seconds(30)) {
        self.store = store
        self.client = client
        self.timeout = timeout
    }

    deinit { task?.cancel(); deadline?.cancel() }

    func generate(_ plan: MeetingSummaryPlan, consent: Bool) async {
        guard consent, state != .sending, plan.sessionID == store.sessionID,
              plan.events == store.finals.sorted(by: { $0.startOffset < $1.startOffset }) else { return }
        let id = UUID()
        operationID = id
        state = .sending
        draft = []
        partialText = ""
        totalSections = plan.requests.count
        let operation = Task { [weak self] in
            for request in plan.requests {
                guard let self, self.accepts(id, session: plan.sessionID), !Task.isCancelled else { return }
                self.requestID = request.id
                self.deadline = Task { [weak self, timeout] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    guard let self, self.accepts(id, session: plan.sessionID), self.requestID == request.id else { return }
                    self.stop(with: .failed(.timeout))
                }
                do {
                    let result = try await self.client.generate(request) { [weak self] text in
                        guard let self, self.accepts(id, session: plan.sessionID), self.requestID == request.id,
                              text.count <= 8_000 else { return }
                        self.partialText = text
                    }
                    guard self.accepts(id, session: plan.sessionID), !Task.isCancelled else { return }
                    let card = try result.card(for: request)
                    guard !card.hasInvalidEvidence, !card.evidenceIDs.isEmpty,
                          let first = request.events.first,
                          let endOffset = request.events.map({ $0.endOffset ?? $0.startOffset }).max() else { throw InsightFailure.invalidResponse }
                    self.deadline?.cancel()
                    self.deadline = nil
                    self.requestID = nil
                    self.draft.append(MeetingSummarySection(id: request.id, text: card.text, evidenceIDs: card.evidenceIDs,
                                                             startOffset: first.startOffset, endOffset: endOffset))
                    self.partialText = ""
                } catch {
                    guard self.accepts(id, session: plan.sessionID) else { return }
                    self.stop(with: .failed(.sanitized(error)))
                    return
                }
            }
            guard let self, self.accepts(id, session: plan.sessionID), !Task.isCancelled else { return }
            self.completed = MeetingSummary(sessionID: plan.sessionID, answerLanguage: plan.answerLanguage, sections: self.draft)
            self.operationID = nil
            self.task = nil
            self.state = .complete
        }
        task = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
            Task { @MainActor [weak self] in
                guard self?.operationID == id else { return }
                self?.cancel()
            }
        }
    }

    func cancel() {
        guard state == .sending else { return }
        stop(with: .interrupted)
    }

    func reset() {
        cancel()
        completed = nil
        draft = []
        partialText = ""
        totalSections = 0
        state = .idle
    }

    private func accepts(_ id: UUID, session: UUID) -> Bool {
        operationID == id && store.sessionID == session && state == .sending
    }

    private func stop(with state: State) {
        operationID = nil
        requestID = nil
        task?.cancel()
        deadline?.cancel()
        task = nil
        deadline = nil
        partialText = ""
        self.state = state
    }
}
