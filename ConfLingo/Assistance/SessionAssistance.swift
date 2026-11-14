import Foundation

/// Shared assistance services; each workspace retains its own session and UI lifecycle.
@MainActor
final class SessionAssistance {
    let store: MeetingSessionStore
    let knowledge: KnowledgeStore
    let ai: InsightCoordinator
    let research: WebResearchCoordinator
    let terms = DocumentTerms()
    private var subscriptions: [EventSubscription<Void>] = []

    init(store: MeetingSessionStore, settings: LLMSettings, client: any InsightClient,
         researchClient: (any LLMWebResearching)? = nil) {
        self.store = store
        let knowledge = KnowledgeStore()
        self.knowledge = knowledge
        ai = InsightCoordinator(store: store, client: client, knowledge: knowledge)
        research = WebResearchCoordinator(store: store, knowledge: knowledge, settings: settings, client: researchClient)
        subscriptions = [
            settings.changes.observe { [weak self] in self?.ai.setPermission(false, after: 0) },
            knowledge.contentChanges.observe { [weak self] in
                guard let self else { return }
                knowledge.setPermission(false)
                ai.setAutomaticKnowledge(false)
                terms.reset()
            }
        ]
    }

    func setPermission(_ allowed: Bool, after offset: TimeInterval) {
        if !allowed { research.setPermission(false) }
        ai.setPermission(allowed, after: offset)
    }

    func resume() { ai.resume() }
    func suspend() { research.cancel(); ai.suspend() }
    func reset() { research.reset(); ai.reset() }
}
