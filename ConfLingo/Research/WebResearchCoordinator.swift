import Foundation
import Observation

@MainActor
@Observable
final class WebResearchCoordinator {
    enum State: Equatable { case idle, researching, complete, failed(String) }
    private(set) var state: State = .idle
    private(set) var permitted = false
    private(set) var answers: [MeetingInsight] = []
    private(set) var requestCount = 0
    var limit = 20
    var draftQuery = ""
    var showsSheet = false
    private(set) var selectedEvidenceIDs: [UUID] = []
    let settings: LLMSettings
    let store: MeetingSessionStore
    let knowledge: KnowledgeStore
    private let client: any LLMWebResearching
    private let timeout: Duration
    @ObservationIgnored private var subscriptions: [EventSubscription<Void>] = []
    private var requestID: UUID?
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var deadline: Task<Void, Never>?

    init(store: MeetingSessionStore, knowledge: KnowledgeStore, settings: LLMSettings,
         client: (any LLMWebResearching)? = nil, timeout: Duration = .seconds(60)) {
        self.store = store
        self.knowledge = knowledge
        self.settings = settings
        self.client = client ?? SelectedLLMResearchClient(settings: settings)
        self.timeout = timeout
        subscriptions = [
            settings.changes.observe { [weak self] in self?.setPermission(false) },
            knowledge.invalidations.observe { [weak self] in self?.setPermission(false) }
        ]
    }

    deinit { operation?.cancel(); deadline?.cancel() }
    var supported: Bool { settings.selected.provider.supportsWebResearch }
    var isBusy: Bool { state == .researching }
    var canRun: Bool { supported && permitted && !isBusy && !knowledge.isBusy && requestCount < max(0, limit) }
    static func validQuestion(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= 2_000
    }
    var status: String {
        if !supported { return ResearchFailure.unsupported.localizedDescription }
        switch state {
        case .idle: return "選択中LLMのWeb検索を使います。調査内容と送信する文脈を確認してください。"
        case .researching: return "LLMがWebを調べ、発話・資料と照合しています…"
        case .complete: return "LLMのWeb調査が完了しました。本文の出典から根拠を確認できます。"
        case .failed(let message): return message
        }
    }

    var contextEvents: [TranscriptEvent] {
        selectedEvidenceIDs.isEmpty ? store.finals : store.finals.filter { selectedEvidenceIDs.contains($0.id) }
    }
    func open(_ text: String, evidenceIDs: [UUID] = []) {
        draftQuery = text
        selectedEvidenceIDs = evidenceIDs
        showsSheet = true
    }
    func setPermission(_ value: Bool) { cancel(); permitted = value }
    func cancel() {
        requestID = nil
        operation?.cancel()
        operation = nil
        deadline?.cancel()
        deadline = nil
        if isBusy { state = .idle }
    }
    func reset() {
        setPermission(false)
        answers = []
        requestCount = 0
        limit = 20
        draftQuery = ""
        selectedEvidenceIDs = []
        showsSheet = false
    }

    func run(question: String, language: AnswerLanguage) async {
        guard canRun else { return }
        guard Self.validQuestion(question) else {
            state = .failed("調査内容は1〜2,000文字で入力してください。")
            return
        }
        let id = UUID()
        let session = store.sessionID
        let version = knowledge.revision
        let connection = settings.revision
        let events = contextEvents
        requestID = id
        state = .researching
        armDeadline(id: id)
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestID == id {
                    self.requestID = nil; self.operation = nil; self.deadline?.cancel(); self.deadline = nil
                    if self.isBusy { self.state = .idle }
                }
            }
            @MainActor func current() -> Bool {
                self.requestID == id && self.permitted && !Task.isCancelled && self.store.sessionID == session
                    && self.knowledge.revision == version && self.settings.revision == connection
            }
            do {
                let references = try await self.knowledge.localReferences(question + " " + events.suffix(3).map(\.text).joined(separator: " "))
                guard current() else { return }
                let request = try InsightRequest(sessionID: session, question: question, trigger: .manual,
                    events: events, answerLanguage: language, knowledge: references, purpose: .webResearch)
                self.requestCount += 1
                let card = try await self.client.generate(request)
                guard current() else { return }
                guard card.id == request.id, card.status == .complete, !card.hasInvalidEvidence,
                      card.kind == .answerSuggestion, card.webReferences?.isEmpty == false,
                      card.evidenceIDs.allSatisfy({ id in request.events.contains { $0.id == id } }),
                      card.knowledgeReferences.allSatisfy({ reference in request.knowledge.contains(reference) }) else {
                    throw InsightFailure.invalidResponse
                }
                self.answers.append(card)
                if self.answers.count > 100 { self.answers.removeFirst(self.answers.count - 100) }
                self.state = .complete
            } catch {
                guard current() else { return }
                let message = (error as? ResearchFailure)?.localizedDescription ?? InsightFailure.sanitized(error).localizedDescription
                self.state = .failed("Web調査を完了できませんでした。" + message)
            }
        }
        operation = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if requestID == id, Task.isCancelled { cancel() }
    }

    private func armDeadline(id: UUID) {
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: self?.timeout ?? .seconds(60)) } catch { return }
            guard let self, self.requestID == id else { return }
            self.cancel()
            self.state = .failed("Web調査がタイムアウトしました。字幕は継続します。必要なら手動で再試行してください。")
        }
    }
}
