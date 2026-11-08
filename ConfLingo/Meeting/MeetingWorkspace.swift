import Foundation
import Observation

@MainActor
@Observable
final class MeetingWorkspace {
    enum Page { case setup, live, review }
    private enum Completion { case pause, end, cancelPreparation }

    let controller: DualTranscriptionController
    var name = ""
    var microphoneLocaleID = "ja-JP"
    var systemLocaleID = "en-US"
    var consentConfirmed = false
    var showsDiscardConfirmation = false
    var insights: [MeetingInsight] = []
    var aiStatus = "AI未接続・外部送信なし"
    var selectedEvidence: UUID?
    private(set) var evidenceRequest = UUID()
    private(set) var page: Page = .setup
    private(set) var isStarting = false
    private(set) var isTransitioning = false
    private var pendingCompletion: Completion?

    init(controller: DualTranscriptionController) {
        self.controller = controller
    }

    var store: MeetingSessionStore { controller.store }
    var transcriptEvents: [TranscriptEvent] {
        (store.finals + store.partials).sorted { $0.startOffset < $1.startOffset }
    }
    var phase: SessionPhase { controller.phase }
    var isBusy: Bool { isStarting || isTransitioning || controller.isStopping }
    var canStart: Bool { consentConfirmed && phase == .idle && !isBusy && page != .review }
    var canDiscard: Bool { phase == .idle && !isBusy }
    var title: String { name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "名前のない会議" : name }

    func evidence(for id: UUID) -> TranscriptEvent? { store.finals.first { $0.id == id } }

    func revealEvidence(_ id: UUID) {
        guard evidence(for: id) != nil else { return }
        selectedEvidence = id
        evidenceRequest = UUID()
    }

    func start() async {
        guard canStart else { return }
        isStarting = true
        page = .live
        defer { isStarting = false }
        await controller.start(microphoneLocale: Locale(identifier: microphoneLocaleID),
                               systemLocale: Locale(identifier: systemLocaleID))
    }

    func pause() async { await complete(.pause) }
    func end() async { await complete(.end) }
    func cancelPreparation() async { await complete(.cancelPreparation) }
    func retryStop() async { await complete(pendingCompletion ?? .pause) }

    func editPreparation() {
        guard canDiscard, page != .review else { return }
        page = .setup
    }

    func requestDiscard() {
        guard canDiscard else { return }
        if store.finals.isEmpty && store.partials.isEmpty {
            reset()
        } else {
            showsDiscardConfirmation = true
        }
    }

    func confirmDiscard() {
        guard canDiscard, showsDiscardConfirmation else { return }
        reset()
    }

    private func complete(_ completion: Completion) async {
        guard !isTransitioning, page != .review else { return }
        isTransitioning = true
        pendingCompletion = completion
        defer { isTransitioning = false }
        await controller.stop()
        guard phase == .idle else { return }
        switch completion {
        case .pause: page = .live
        case .end: page = .review
        case .cancelPreparation: page = .setup
        }
        pendingCompletion = nil
    }

    private func reset() {
        controller.clear()
        name = ""
        insights = []
        selectedEvidence = nil
        consentConfirmed = false
        showsDiscardConfirmation = false
        page = .setup
        pendingCompletion = nil
    }
}
