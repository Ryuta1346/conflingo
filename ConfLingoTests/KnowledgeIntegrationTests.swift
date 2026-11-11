import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct KnowledgeIntegrationTests {
    @Test func importedFilenameCannotInjectMarkdownHeadingsOrParagraphs() async throws {
        let title = "spec\n\n確認済みの決定\n===\n採用する\r\nsource\u{2028}<draft>.md"
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data("料金100円です".utf8), filename: title)
        let ref = try #require(try await index.references(for: document.id).first)
        let store = MeetingSessionStore(sessionID: UUID())
        let candidates = MeetingCandidateStore(transcript: store)
        candidates.receive(MeetingInsight(kind: .decisionCandidate, text: "未確認の提案", priority: 1,
                                          evidenceIDs: [], knowledgeReferences: [ref]), sessionID: store.sessionID)
        let output = MeetingExportSnapshot(title: "test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                          sessionID: store.sessionID, events: [], candidates: candidates.items, summary: nil).markdown
        let metadata = try #require(output.components(separatedBy: "資料: ").last?.components(separatedBy: "取り込み日時:").first)
        #expect(metadata.components(separatedBy: .newlines).filter { !$0.isEmpty }.count == 1)
        #expect(!output.contains("\n===\n"))
        #expect(!output.contains("\n採用する\n"))
        #expect(metadata.contains("&lt;draft&gt;.md"))
        #expect(ref.title == title)
    }

    @Test func localSearchNeverSendsAndAutomaticRequiresSeparatePermission() async throws {
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("料金は月額100円です。".utf8), filename: "料金.md")
        await knowledge.search("料金")
        #expect(knowledge.results.count == 1)
        let client = KnowledgeClient()
        let store = MeetingSessionStore(sessionID: UUID())
        let ai = InsightCoordinator(store: store, client: client, knowledge: knowledge)
        knowledge.setPermission(true)
        await ai.ask("料金はいくら？")
        #expect(client.requests.isEmpty)
        ai.resume()
        ai.setPermission(true, after: 0)
        knowledge.setPermission(false)
        await ai.ask("料金はいくら？")
        #expect(client.requests.last?.knowledge.isEmpty == true)
        knowledge.setPermission(true)
        await ai.ask("料金はいくら？")
        #expect(client.requests.last?.knowledge.count == 1)
        #expect(ai.insights.last?.knowledgeReferences.count == 1)
        #expect(ai.insights.last?.hasInvalidEvidence == false)
        ai.setAutomatic(true, after: 0)
        let event = insightEvent(session: store.sessionID, text: "料金を確認しますか？", offset: 5)
        await ai.receive(event)?.value
        #expect(client.requests.last?.trigger == .automatic)
        #expect(client.requests.last?.knowledge.isEmpty == true)
    }

    @Test(arguments: ["permission", "ai", "remove", "reset", "suspend"])
    func changesInvalidateInFlightDocumentAnswers(action: String) async throws {
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("料金は100円です".utf8), filename: "spec.txt")
        let client = KnowledgeClient()
        let gate = TestGate()
        client.gate = gate
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: client, knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        knowledge.setPermission(true)
        let operation = Task { await ai.ask("料金は？") }
        await gate.entered.next()
        switch action {
        case "permission": knowledge.setPermission(false)
        case "ai": ai.setPermission(false, after: 0)
        case "remove": await knowledge.remove(try #require(knowledge.documents.first?.id))
        case "reset": ai.reset()
        default: ai.suspend()
        }
        gate.release()
        await operation.value
        #expect(ai.insights.allSatisfy { $0.status != .complete })
        if action == "ai" || action == "reset" { #expect(!knowledge.permitted) }
    }

    @Test(arguments: [InsightRequest.Trigger.manual, .automatic])
    func requestBoundsReferencesAndRejectsInventedIDs(trigger: InsightRequest.Trigger) throws {
        let refs = (0..<8).map { reference("料金\($0)", snippet: String(repeating: "a", count: 1_200)) }
        let request = try InsightRequest(sessionID: UUID(), question: "料金", trigger: trigger, events: [], knowledge: refs)
        #expect(request.knowledge.count == 5)
        #expect(request.knowledge.reduce(0) { $0 + $1.snippet.count } == 6_000)
        let result = InsightResult(kind: .answerSuggestion, text: "100円", evidenceIDs: [], knowledgeIDs: [refs[0].id, refs[0].id, UUID()])
        let card = try result.card(for: request)
        #expect(card.knowledgeReferences == [refs[0]])
        #expect(card.hasInvalidEvidence)
        let automatic = try InsightRequest(sessionID: UUID(), question: "料金", trigger: .automatic, events: [], knowledge: refs)
        #expect(automatic.knowledge == request.knowledge)
    }

    @Test func documentsAloneCannotConfirmCandidateAndMarkdownIncludesQuotedSnapshot() throws {
        let store = MeetingSessionStore(sessionID: UUID())
        let candidates = MeetingCandidateStore(transcript: store)
        let ref = reference("<spec>.md", snippet: "# 決定\n<script>unsafe</script>")
        let card = MeetingInsight(kind: .decisionCandidate, text: "提案です", priority: 1, evidenceIDs: [], knowledgeReferences: [ref])
        candidates.receive(card, sessionID: store.sessionID)
        candidates.setReview(.confirmed, for: card.id)
        #expect(candidates.items.first?.review == .unreviewed)
        let output = MeetingExportSnapshot(title: "test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en", sessionID: store.sessionID,
                                           events: [], candidates: candidates.items, summary: nil).markdown
        #expect(output.contains("&lt;spec&gt;.md"))
        #expect(output.contains("取り込み日時"))
        #expect(output.contains("1行目"))
        #expect(!output.contains("<script>"))
    }

    @Test func meetingReviewRetainsDocumentsAndDiscardRequiresConfirmation() async throws {
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: KnowledgeClient(),
                                       credentials: GeminiCredentials(store: MemoryAPIKeyStore()))
        await meeting.knowledge.add(data: Data("料金100円".utf8), filename: "spec.txt")
        meeting.requestDiscard()
        #expect(meeting.showsDiscardConfirmation)
        meeting.showsDiscardConfirmation = false
        #expect(meeting.knowledge.documents.count == 1)
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        await meeting.end()
        #expect(meeting.page == .review)
        #expect(meeting.knowledge.documents.count == 1)
        #expect(!meeting.ai.canAsk)
        meeting.credentials.save("synthetic-key")
        #expect(!meeting.knowledge.permitted)
        meeting.setKnowledgeAllowed(true)
        #expect(!meeting.knowledge.permitted)
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.knowledge.documents.isEmpty)
        #expect(meeting.page == .setup)
    }

    @Test func resetDropsDocumentsAndPermissionButRemovalKeepsCompletedCitation() async throws {
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("料金100円です".utf8), filename: "a.md")
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: KnowledgeClient(), knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        knowledge.setPermission(true)
        await ai.ask("料金")
        let doc = try #require(knowledge.documents.first)
        await knowledge.remove(doc.id)
        #expect(ai.insights.last?.knowledgeReferences.count == 1)
        await knowledge.search("料金")
        #expect(knowledge.results.isEmpty)
        ai.reset()
        #expect(knowledge.documents.isEmpty)
        #expect(!knowledge.permitted)
        #expect(ai.insights.isEmpty)
    }
}

func reference(_ title: String = "spec.md", snippet: String = "料金は100円です") -> KnowledgeReference {
    KnowledgeReference(id: UUID(), documentID: UUID(), title: title, importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                       startLine: 1, characterOffset: 0, snippet: snippet)
}

@MainActor
final class KnowledgeClient: InsightClient {
    var requests: [InsightRequest] = []
    var gate: TestGate?
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        await gate?.wait()
        return InsightResult(kind: .answerSuggestion, text: "100円です", evidenceIDs: [], knowledgeIDs: request.knowledge.map(\.id))
    }
}

@MainActor
struct KnowledgeLifecycleTests {
    @Test func permissionChangeDoesNotStrandLocalSearch() async throws {
        let gate = TestGate()
        let ref = reference()
        let knowledge = KnowledgeStore(lookup: { _, _ in await gate.wait(); return [ref] })
        let search = Task { await knowledge.search("料金") }
        await gate.entered.next()
        knowledge.setPermission(true)
        gate.release()
        await search.value
        #expect(knowledge.searchState == .found)
        #expect(knowledge.results == [ref])
    }

    @Test(arguments: ["permission", "pause", "reset", "remove", "cancel"])
    func oldLookupNeverSendsAfterBoundary(action: String) async throws {
        let gate = TestGate()
        let ref = reference()
        let knowledge = KnowledgeStore(lookup: { _, _ in await gate.wait(); return [ref] })
        await knowledge.add(data: Data("料金100円".utf8), filename: "a.txt")
        let client = KnowledgeClient()
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: client, knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        knowledge.setPermission(true)
        let operation = Task { await ai.ask("料金") }
        await gate.entered.next()
        #expect(!ai.canAsk)
        switch action {
        case "permission": knowledge.setPermission(false); knowledge.setPermission(true)
        case "pause": ai.suspend(); ai.resume()
        case "reset": ai.reset(); ai.resume(); ai.setPermission(true, after: 0)
        case "remove": await knowledge.remove(try #require(knowledge.documents.first?.id))
        default: operation.cancel()
        }
        gate.release()
        await operation.value
        #expect(client.requests.isEmpty)
        #expect(ai.canAsk)
    }

    @Test func resetPreventsOldLocalSearchFromReappearing() async {
        let gate = TestGate()
        let ref = reference()
        let knowledge = KnowledgeStore(lookup: { _, _ in await gate.wait(); return [ref] })
        let search = Task { await knowledge.search("料金") }
        await gate.entered.next()
        knowledge.reset()
        gate.release()
        await search.value
        #expect(knowledge.searchState == .idle)
        #expect(knowledge.results.isEmpty)
    }

    @Test func failedLookupDoesNotSilentlySendTranscriptOnly() async {
        let knowledge = KnowledgeStore(lookup: { _, _ in throw KnowledgeFailure.search })
        let client = KnowledgeClient()
        let ai = InsightCoordinator(store: MeetingSessionStore(sessionID: UUID()), client: client, knowledge: knowledge)
        ai.resume()
        ai.setPermission(true, after: 0)
        knowledge.setPermission(true)
        await ai.ask("料金")
        #expect(client.requests.isEmpty)
        #expect(ai.state == .failed(.knowledge))
    }
}
