import Foundation
import Observation

@MainActor
@Observable
final class MeetingWorkspace {
    enum Page { case setup, live, review }
    private enum Completion { case pause, end, cancelPreparation }

    let translations: MeetingTranslations
    var mode: SessionMode = .transcription
    var inputSelection: AudioInputSelection = .both
    var microphoneTranslationLanguage: String { didSet { defaults.set(microphoneTranslationLanguage, forKey: "meetingMicrophoneTranslation") } }
    var systemTranslationLanguage: String { didSet { defaults.set(systemTranslationLanguage, forKey: "meetingSystemTranslation") } }
    let controller: DualTranscriptionController
    private let defaults: UserDefaults
    var answerLanguage: AnswerLanguage {
        didSet {
            defaults.set(answerLanguage.rawValue, forKey: "aiAnswerLanguage")
            ai.answerLanguage = answerLanguage
            cancelSummary()
        }
    }
    var isSavingSession = false
    var name = ""
    var microphoneLocaleID = "ja-JP"
    var systemLocaleID = "en-US"
    var consentConfirmed = false
    var showsDiscardConfirmation = false
    var knowledge: KnowledgeStore { support.knowledge }
    var selectedKnowledge: KnowledgeReference?
    var isUsingLibrary = false
    var documentTerms: DocumentTerms { support.terms }
    var recognitionMode: SpeechRecognitionMode = .standard
    var recognitionStatus = "認識用語は次回の開始時に適用します。"
    let support: SessionAssistance
    var ai: InsightCoordinator { support.ai }
    var research: WebResearchCoordinator { support.research }
    let summary: MeetingSummaryCoordinator
    let export = MeetingExportState()
    var startedAt: Date? { controller.startedAt }
    private var pendingSummaryID: UUID?
    private var preparingSummaryID: UUID?
    var candidates: MeetingCandidateStore { ai.candidates }
    let llmSettings: LLMSettings
    var credentials: APIKeyCredentials { llmSettings.credentials }
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
        if summary.state == .sending { return "会議の要約を\(llmSettings.selected.name)へ送信中" }
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
    @ObservationIgnored private var subscriptions: [EventSubscription<Void>] = []
    @ObservationIgnored private var finalSubscription: EventSubscription<TranscriptEvent>?
    @ObservationIgnored private var captureSubscription: EventSubscription<Bool>?

    init(controller: DualTranscriptionController, insightClient: (any InsightClient)? = nil,
         credentials: APIKeyCredentials? = nil, defaults: UserDefaults = .standard, llmSettings: LLMSettings? = nil,
         translationClientFactory: @escaping (String, String) -> any MeetingTranslating = { _, _ in AppleMeetingTranslator() }, prepareTranslationModels: Bool = true,
         researchClient: (any LLMWebResearching)? = nil) {
        self.defaults = defaults
        microphoneTranslationLanguage = defaults.string(forKey: "meetingMicrophoneTranslation") ?? "en"
        systemTranslationLanguage = defaults.string(forKey: "meetingSystemTranslation") ?? "ja"
        translations = MeetingTranslations(sessionID: controller.store.sessionID, clientFactory: translationClientFactory, requiresPreparation: prepareTranslationModels)
        let language = AnswerLanguage(rawValue: defaults.string(forKey: "aiAnswerLanguage") ?? "") ?? .japanese
        answerLanguage = language
        self.controller = controller
        let settings = llmSettings ?? LLMSettings(defaults: defaults, legacyCredentials: credentials)
        self.llmSettings = settings
        let client = insightClient ?? SelectedLLMClient(settings: settings)
        let support = SessionAssistance(store: controller.store, settings: settings, client: client, researchClient: researchClient)
        self.support = support
        support.ai.answerLanguage = language
        summary = MeetingSummaryCoordinator(store: controller.store, client: client)
        subscriptions = [
            knowledge.invalidations.observe { [weak self] in self?.cancelSummary() },
            knowledge.contentChanges.observe { [weak self] in
                Task { [weak self] in await self?.applyDocumentTerms() }
            },
            settings.changes.observe { [weak self] in self?.cancelSummary() }
        ]
        translations.termsForRequest = { [weak self] request in
            self?.documentTerms.glossary(sourceLanguage: request.event.languageCode,
                targetLanguage: request.targetLanguage, manual: []).map(\.term) ?? []
        }
        finalSubscription = controller.store.finalEvents.observe { [weak self] event in
            guard let self else { return }
            let target = event.origin == .microphone ? self.microphoneTranslationLanguage : self.systemTranslationLanguage
            self.translations.receive(event, targetLanguage: self.mode.translationTarget(source: event.languageCode, target: target))
        }
        controller.prepareOptionalConsumer = { [weak support] hub in await support?.ai.attach(to: hub) }
        captureSubscription = controller.captureActivityChanges.observe { [weak support] active in
            if active { support?.resume() } else { support?.suspend() }
        }
    }

    func summaryPlan() throws -> MeetingSummaryPlan {
        cancelSummary()
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: answerLanguage)
        pendingSummaryID = plan.id
        return plan
    }

    func summaryPlan(includingKnowledge: Bool) async throws -> MeetingSummaryPlan {
        if !includingKnowledge { return try summaryPlan() }
        guard !knowledge.isBusy else { throw KnowledgeFailure.search }
        cancelSummary()
        let preparation = UUID()
        preparingSummaryID = preparation
        defer { if preparingSummaryID == preparation { preparingSummaryID = nil } }
        let base = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: answerLanguage)
        let version = knowledge.revision
        var groups: [[KnowledgeReference]] = []
        for request in base.requests {
            groups.append(try await knowledge.retrieveForSummary(request.events))
            guard preparingSummaryID == preparation, version == knowledge.revision, !Task.isCancelled else { throw CancellationError() }
        }
        guard base.sessionID == store.sessionID, base.answerLanguage == answerLanguage,
              base.events == store.finals.sorted(by: { $0.startOffset < $1.startOffset }) else { throw CancellationError() }
        let plan = try MeetingSummaryPlan(sessionID: base.sessionID, events: base.events, answerLanguage: base.answerLanguage,
                                          knowledgeBySection: groups, knowledgeRevision: version)
        pendingSummaryID = plan.id
        return plan
    }

    func isSummaryPlanCurrent(_ plan: MeetingSummaryPlan) -> Bool {
        pendingSummaryID == plan.id && plan.sessionID == store.sessionID && plan.answerLanguage == answerLanguage
            && (plan.knowledgeRevision == nil || (plan.knowledgeRevision == knowledge.revision && !knowledge.isBusy))
            && plan.events == store.finals.sorted(by: { $0.startOffset < $1.startOffset })
    }

    func generateSummary(_ plan: MeetingSummaryPlan, consent: Bool) async {
        guard consent, page == .review, phase == .idle, !isBusy, isSummaryPlanCurrent(plan) else { return }
        pendingSummaryID = nil
        await summary.generate(plan, consent: consent)
    }

    func cancelSummary() {
        preparingSummaryID = nil
        pendingSummaryID = nil
        summary.cancel()
    }

    var exportSnapshot: MeetingExportSnapshot? {
        guard page == .review || (page == .setup && !completedAssistance.isEmpty),
              phase == .idle, !isBusy else { return nil }
        return MeetingExportSnapshot(title: title, startedAt: startedAt, microphoneLocale: microphoneLocaleID,
                                     systemLocale: systemLocaleID, sessionID: store.sessionID,
                                     events: store.finals, candidates: candidates.items, summary: summary.completed,
                                     translations: translations.completed, assistance: completedAssistance)
    }

    var completedAssistance: [MeetingInsight] { insights.filter { $0.status == .complete } + research.answers }

    var canAskAssistance: Bool {
        ai.permitted && page != .review && !isBusy && !knowledge.isBusy
            && (phase == .idle || phase == .listening) && ai.state != .sending
    }

    func askAssistance(_ question: String) async {
        guard canAskAssistance else { return }
        if phase == .idle { support.resume() }
        await ai.ask(question)
    }

    func setAIAllowed(_ allowed: Bool) {
        if !allowed { cancelSummary() }
        guard !allowed || (page != .review && phase != .stopping) else { return }
        support.setPermission(allowed, after: controller.elapsedOffset)
    }

    func setKnowledgeAllowed(_ allowed: Bool) {
        guard !allowed || (ai.permitted && page != .review && phase != .stopping) else { return }
        knowledge.setPermission(allowed)
    }

    func setAutomaticKnowledgeAllowed(_ allowed: Bool) {
        guard !allowed || (page != .review && phase != .stopping && !knowledge.isBusy) else { return }
        ai.setAutomaticKnowledge(allowed)
    }

    func importKnowledge(_ url: URL) async {
        guard canEditKnowledge else { return }
        await knowledge.add(url: url)
    }

    func importRepository(_ scan: RepositoryScan, selected: Set<String>) async {
        guard canEditKnowledge else { return }
        await knowledge.importRepository(scan, selected: selected)
    }

    func setAutomaticAI(_ allowed: Bool) {
        ai.setAutomatic(allowed, after: controller.elapsedOffset)
    }

    var store: MeetingSessionStore { controller.store }
    var transcriptEvents: MeetingTranscriptTimeline<[TranscriptEvent]> {
        MeetingTranscriptTimeline(finals: store.finals, partials: store.partials)
    }
    var phase: SessionPhase { controller.phase }
    var isBusy: Bool { isStarting || isTransitioning || controller.isStopping }
    var canEditKnowledge: Bool {
        page != .review && (phase == .idle || phase == .listening)
            && !isBusy && !isUsingLibrary && !isSavingSession && !knowledge.isBusy
    }
    var canStart: Bool { consentConfirmed && phase == .idle && !isBusy && !knowledge.isBusy && !isUsingLibrary && page != .review }
    var canDiscard: Bool { phase == .idle && !isBusy && !knowledge.isBusy && !isUsingLibrary && !isSavingSession }
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
                               systemLocale: Locale(identifier: systemLocaleID), recognitionMode: recognitionMode,
                               contextKeywords: recognitionKeywords, selection: inputSelection)
    }

    func translationTarget(for event: TranscriptEvent) -> String? {
        if let entry = translations.entries[event.id] { return entry.request.targetLanguage }
        guard !event.isFinal else { return nil }
        let target = event.origin == .microphone ? microphoneTranslationLanguage : systemTranslationLanguage
        return mode.translationTarget(source: event.languageCode, target: target)
    }

    func pause() async { await complete(.pause) }

    var recognitionKeywords: [AudioOrigin: [String]] {
        [.microphone: documentTerms.glossary(sourceLanguage: microphoneLocaleID, targetLanguage: nil, manual: []).map(\.term),
         .systemAudio: documentTerms.glossary(sourceLanguage: systemLocaleID, targetLanguage: nil, manual: []).map(\.term)]
    }

    func applyDocumentTerms() async {
        guard phase == .listening, recognitionMode == .vocabulary else {
            recognitionStatus = recognitionMode == .standard ? "用語ヒントは「資料の用語を優先」で使用します。方式は開始前に選択します。" : "認識用語は次回の開始時に適用します。"
            return
        }
        let revision = documentTerms.revision
        let updated = await controller.updateContext(recognitionKeywords)
        guard revision == documentTerms.revision else { return }
        recognitionStatus = updated ? "認識エンジンへ用語を反映しました。認識精度への効果は未評価です。" : "認識用語は未反映です。次回の開始時に適用します。"
    }
    func end() async { await complete(.end) }
    func cancelPreparation() async { await complete(.cancelPreparation) }
    func retryStop() async { await complete(pendingCompletion ?? .pause) }

    func editPreparation() {
        guard canDiscard, page != .review else { return }
        support.suspend()
        page = .setup
    }

    func requestDiscard() {
        guard canDiscard else { return }
        if store.finals.isEmpty && store.partials.isEmpty && insights.isEmpty && research.answers.isEmpty && knowledge.documents.isEmpty {
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
        knowledge.cancelPendingImports()
        support.suspend()
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
        support.reset()
        controller.clear()
        translations.reset(sessionID: store.sessionID)
        mode = .transcription
        name = ""
        insights = []
        selectedEvidence = nil
        selectedKnowledge = nil
        consentConfirmed = false
        showsDiscardConfirmation = false
        page = .setup
        pendingCompletion = nil
    }
}
