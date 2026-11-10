import Foundation
import Observation

@MainActor
@Observable
final class MeetingWorkspace {
    enum Page { case setup, live, review }
    private enum Completion { case pause, end, cancelPreparation }

    let controller: DualTranscriptionController
    private let defaults: UserDefaults
    var answerLanguage: AnswerLanguage {
        didSet {
            defaults.set(answerLanguage.rawValue, forKey: "aiAnswerLanguage")
            ai.answerLanguage = answerLanguage
        }
    }
    var name = ""
    var microphoneLocaleID = "ja-JP"
    var systemLocaleID = "en-US"
    var consentConfirmed = false
    var showsDiscardConfirmation = false
    let ai: InsightCoordinator
    let summary: MeetingSummaryCoordinator
    let export = MeetingExportState()
    var startedAt: Date? { controller.startedAt }
    private var pendingSummaryID: UUID?
    var candidates: MeetingCandidateStore { ai.candidates }
    let credentials: GeminiCredentials
    var insights: [MeetingInsight] {
        get { ai.insights }
        set {
            ai.insights = newValue
            for card in newValue { candidates.receive(card, sessionID: store.sessionID) }
        }
    }
    #if DEBUG
    var previewAIStatus: String?
    var previewUsesLiveAI = false
    #endif
    var canStopAI: Bool { ai.permitted || summary.state == .sending }
    var aiStatus: String {
        if summary.state == .sending { return "会議の要約をGeminiへ送信中" }
        #if DEBUG
        if let previewAIStatus { return previewAIStatus }
        #endif
        return ai.statusText
    }
    var selectedEvidence: UUID?
    private(set) var evidenceRequest = UUID()
    private(set) var page: Page = .setup
    private(set) var isStarting = false
    private(set) var isTransitioning = false
    private var pendingCompletion: Completion?

    init(controller: DualTranscriptionController, insightClient: (any InsightClient)? = nil,
         credentials: GeminiCredentials? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let language = AnswerLanguage(rawValue: defaults.string(forKey: "aiAnswerLanguage") ?? "") ?? .japanese
        answerLanguage = language
        self.controller = controller
        let credentials = credentials ?? GeminiCredentials()
        self.credentials = credentials
        let client = insightClient ?? GeminiInsightClient(key: { try await credentials.store.read() })
        let ai = InsightCoordinator(store: controller.store, client: client)
        ai.answerLanguage = language
        self.ai = ai
        let summary = MeetingSummaryCoordinator(store: controller.store, client: client)
        self.summary = summary
        controller.prepareOptionalConsumer = { [weak ai] hub in await ai?.attach(to: hub) }
        controller.captureActivityChanged = { [weak ai] active in
            if active { ai?.resume() } else { ai?.suspend() }
        }
        credentials.onChange = { [weak self] in
            self?.ai.setPermission(false, after: 0)
            self?.cancelSummary()
        }
    }

    func summaryPlan() throws -> MeetingSummaryPlan {
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: answerLanguage)
        pendingSummaryID = plan.id
        return plan
    }

    func generateSummary(_ plan: MeetingSummaryPlan, consent: Bool) async {
        guard consent, page == .review, phase == .idle, !isBusy, pendingSummaryID == plan.id else { return }
        pendingSummaryID = nil
        await summary.generate(plan, consent: consent)
    }

    func cancelSummary() {
        pendingSummaryID = nil
        summary.cancel()
    }

    var exportSnapshot: MeetingExportSnapshot? {
        guard page == .review, phase == .idle, !isBusy else { return nil }
        return MeetingExportSnapshot(title: title, startedAt: startedAt, microphoneLocale: microphoneLocaleID,
                                     systemLocale: systemLocaleID, sessionID: store.sessionID,
                                     events: store.finals, candidates: candidates.items, summary: summary.completed)
    }

    func setAIAllowed(_ allowed: Bool) {
        if !allowed { cancelSummary() }
        guard !allowed || (page != .review && phase != .stopping) else { return }
        ai.setPermission(allowed, after: controller.elapsedOffset)
    }

    func setAutomaticAI(_ allowed: Bool) {
        ai.setAutomatic(allowed, after: controller.elapsedOffset)
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
        ai.suspend()
        page = .setup
    }

    func requestDiscard() {
        guard canDiscard else { return }
        if store.finals.isEmpty && store.partials.isEmpty && insights.isEmpty {
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
        ai.suspend()
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
        cancelSummary()
        summary.reset()
        export.reset()
        ai.reset()
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
