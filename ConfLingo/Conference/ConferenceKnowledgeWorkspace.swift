import Foundation
import Observation

@MainActor
@Observable
final class ConferenceKnowledgeWorkspace {
    let store: SessionStore
    let settings: LLMSettings
    let knowledge = KnowledgeStore()
    let terms = DocumentTerms()
    var recognitionMode: SpeechRecognitionMode = .standard
    var recognitionStatus = "認識用語は次回の開始時に適用します。"
    let client: any InsightClient
    var answerLanguage: AnswerLanguage = .japanese
    private(set) var questionPermitted = false
    private(set) var correctionPermitted = false
    private(set) var corrections: [ConferenceCorrection] = []
    private(set) var answers: [MeetingInsight] = []
    private(set) var isGenerating = false
    private(set) var preview = ""
    var message = ""
    private var permissionRevision = 0
    private var requestID: UUID?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?
    private let timeout: Duration

    init(store: SessionStore, settings: LLMSettings, client: (any InsightClient)? = nil, timeout: Duration = .seconds(30)) {
        self.store = store
        self.settings = settings
        self.client = client ?? SelectedLLMClient(settings: settings)
        self.timeout = timeout
        knowledge.onContentChange = { [weak self] in self?.revokePermissions(); self?.terms.reset() }
        settings.observeChanges { [weak self] in self?.revokePermissions() }
    }

    deinit { operation?.cancel(); deadline?.cancel() }

    var canEditKnowledge: Bool { (store.phase == .idle || store.phase == .listening) && !knowledge.isBusy }
    var canAsk: Bool { canEditKnowledge && questionPermitted && !isGenerating && !knowledge.documents.isEmpty }

    func setQuestionPermission(_ allowed: Bool) {
        cancel()
        permissionRevision += 1
        questionPermitted = allowed && canEditKnowledge
        knowledge.setPermission(questionPermitted)
    }

    func revokePermissions() {
        setQuestionPermission(false)
        correctionPermitted = false
    }

    func setCorrectionPermission(_ allowed: Bool) {
        cancel()
        permissionRevision += 1
        correctionPermitted = allowed && canEditKnowledge
    }

    var snapshot: ConferenceSupportSnapshot {
        ConferenceSupportSnapshot(answers: answers, corrections: corrections.filter(\.adopted), terms: terms.applied)
    }

    func adoptCorrection(_ id: UUID, adopted: Bool) {
        guard let index = corrections.firstIndex(where: { $0.id == id }),
              let unit = store.units.first(where: { $0.id == corrections[index].unitID }),
              (try? corrections[index].validate(unit: unit)) != nil else { return }
        if adopted {
            for other in corrections.indices where corrections[other].unitID == unit.id { corrections[other].adopted = false }
        }
        corrections[index].adopted = adopted
    }

    func ask(_ question: String) async {
        guard canAsk else { return }
        await perform {
            let references = try await self.knowledge.retrieve(question)
            return try InsightRequest(sessionID: self.store.sessionID, question: question, trigger: .manual,
                events: [], answerLanguage: self.answerLanguage, knowledge: references, purpose: .documentQuestion)
        } accept: { request, result in
            let card = try result.card(for: request)
            guard !card.hasInvalidEvidence, card.evidenceIDs.isEmpty,
                  card.kind == .answerSuggestion || card.kind == .followUpQuestion else { throw InsightFailure.invalidResponse }
            self.answers.append(card)
        }
    }

    func correct(unitID: UUID, sourceLanguage: String, targetLanguage: String?) async {
        guard correctionPermitted, canEditKnowledge, !isGenerating,
              let unit = store.units.first(where: { $0.id == unitID }) else { return }
        let original = TranscriptCorrectionInput(sourceText: unit.english, translation: unit.japanese,
            sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, terms: terms.applied)
        await perform {
            let references = try await self.knowledge.localReferences(unit.english)
            guard !references.isEmpty else { throw InsightFailure.knowledge }
            var request = try InsightRequest(sessionID: self.store.sessionID, question: "Correct the quoted transcript using relevant documents.",
                trigger: .manual, events: [], knowledge: references, purpose: .transcriptCorrection)
            request.correction = original
            return request
        } accept: { request, result in
            let card = try result.card(for: request)
            guard !card.hasInvalidEvidence, result.evidenceIDs.isEmpty, result.kind == .answerSuggestion else { throw InsightFailure.invalidResponse }
            let correction = ConferenceCorrection(id: request.id, unitID: unitID, original: original, sourceText: result.text,
                translation: targetLanguage == nil ? nil : result.supplement, references: card.knowledgeReferences)
            guard let current = self.store.units.first(where: { $0.id == unitID }) else { throw CancellationError() }
            try correction.validate(unit: current)
            self.corrections.append(correction)
        }
    }

    private func perform(_ makeRequest: @escaping () async throws -> InsightRequest,
                         accept: @escaping (InsightRequest, InsightResult) throws -> Void) async {
        cancel()
        let id = UUID()
        requestID = id
        let revision = permissionRevision
        let connection = settings.revision
        let vocabulary = terms.revision
        let session = store.sessionID
        isGenerating = true
        message = ""
        let task = Task { [weak self] in
            guard let self else { return }
            defer { if requestID == id { finish() } }
            @MainActor func current() -> Bool {
                requestID == id && revision == permissionRevision && connection == settings.revision
                    && session == store.sessionID && vocabulary == terms.revision && !Task.isCancelled
            }
            do {
                let request = try await makeRequest()
                guard current() else { return }
                let result = try await client.generate(request) { [weak self] text in
                    if self?.requestID == id { self?.preview = String(text.prefix(8_000)) }
                }
                guard current() else { return }
                try accept(request, result)
            } catch {
                if requestID == id { message = InsightFailure.sanitized(error).localizedDescription }
            }
        }
        operation = task
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, requestID == id else { return }
            cancel()
            message = InsightFailure.timeout.localizedDescription
        }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    func cancel() {
        operation?.cancel()
        finish()
    }

    private func finish() {
        requestID = nil
        operation = nil
        deadline?.cancel()
        deadline = nil
        isGenerating = false
        preview = ""
    }

    func stop() { cancel(); knowledge.cancelPendingImports() }

    func reset() {
        stop()
        revokePermissions()
        knowledge.reset()
        terms.reset()
        answers = []
        corrections = []
        message = ""
    }
}
