import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepositorySummaryTests {
    @Test func reviewPreviewUsesSyntheticRepositoryAndNeverNeedsCredentials() async throws {
        let meeting = MeetingPreview.make(activity: AudioInputUse(), scenario: "repository-review")
        await MeetingPreview.prepare(meeting, scenario: "repository-review")
        #expect(meeting.page == .review)
        #expect(meeting.knowledge.hasRepository)
        let plan = try await meeting.summaryPlan(includingKnowledge: true)
        #expect(!plan.requests[0].knowledge.isEmpty)
        await meeting.generateSummary(plan, consent: true)
        #expect(meeting.summary.completed?.sections.first?.knowledgeReferences.isEmpty == false)
        #expect(meeting.summary.completed?.sections.first?.supplement.isEmpty == false)
    }

    @Test func searchesBeyondFirstTwoThousandCharactersAndDoesNotReuseLivePermission() async throws {
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: RepositorySummaryClient())
        await meeting.knowledge.add(data: Data("refundPayment は返金処理。".utf8), filename: "design.md")
        meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: String(repeating: " unrelated", count: 300) + " refundPayment の採用は未決定。"))
        #expect(!meeting.knowledge.permitted)
        let plan = try await meeting.summaryPlan(includingKnowledge: true)
        #expect(plan.requests.count == 1)
        #expect(plan.requests[0].knowledge.count == 1)
        #expect(plan.requests[0].timeoutSeconds == 60)
        #expect(plan.knowledgeRevision == meeting.knowledge.revision)
        #expect(!meeting.knowledge.permitted)
        let ordinary = try meeting.summaryPlan()
        #expect(ordinary.requests.allSatisfy { $0.knowledge.isEmpty })
    }

    @Test func summarySeparatesSupplementAndExportsItsCitations() async throws {
        let store = summaryStore(count: 1)
        let ref = reference("design.md", snippet: "refundPayment は実装されている。")
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese,
                                          knowledgeBySection: [[ref]], knowledgeRevision: UUID())
        let client = RepositorySummaryClient()
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        await summary.generate(plan, consent: false)
        #expect(client.requests.isEmpty)
        await summary.generate(plan, consent: true)
        let completed = try #require(summary.completed)
        #expect(completed.sections[0].supplement == "資料には返金処理の実装があります。")
        #expect(completed.sections[0].knowledgeReferences == [ref])
        let output = MeetingExportSnapshot(title: "test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                            sessionID: store.sessionID, events: store.finals, candidates: [], summary: completed).markdown
        #expect(output.contains("会議の要約"))
        #expect(output.contains("資料・実装からの補足"))
        #expect(output.contains("design.md"))
        #expect(output.contains(ref.snippet))
    }

    @Test(arguments: ["missingSupplement", "noCitation", "unknownCitation", "noSpeech", "emptySupplementWithCitation"])
    func invalidSupplementCannotBecomeCompletedSummary(mode: String) async throws {
        let store = summaryStore(count: 1)
        let client = RepositorySummaryClient()
        client.mode = mode
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese,
                                          knowledgeBySection: [[reference()]], knowledgeRevision: UUID())
        let summary = MeetingSummaryCoordinator(store: store, client: client)
        await summary.generate(plan, consent: true)
        #expect(summary.completed == nil)
        #expect(summary.state == .failed(.invalidResponse))
    }

    @Test func removalInvalidatesPreparedPlanAndCancelsRunningSummary() async throws {
        let client = RepositorySummaryClient()
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client)
        await meeting.knowledge.add(data: Data("refundPayment".utf8), filename: "design.md")
        meeting.store.receive(insightEvent(session: meeting.store.sessionID, text: "refundPayment"))
        await meeting.end()
        let stale = try await meeting.summaryPlan(includingKnowledge: true)
        await meeting.knowledge.remove(try #require(meeting.knowledge.documents.first?.id))
        await meeting.generateSummary(stale, consent: true)
        #expect(client.requests.isEmpty)
        await meeting.knowledge.add(data: Data("refundPayment".utf8), filename: "design.md")
        let plan = try await meeting.summaryPlan(includingKnowledge: true)
        let gate = TestGate()
        client.gate = gate
        let task = Task { await meeting.generateSummary(plan, consent: true) }
        await gate.entered.next()
        await meeting.knowledge.remove(try #require(meeting.knowledge.documents.first?.id))
        gate.release()
        await task.value
        #expect(meeting.summary.completed == nil)
        #expect(meeting.summary.state == .interrupted)
    }

    @Test func transportUsesSummaryOnlySupplementSchemaAndWorkingTreeProvenance() async throws {
        var ref = reference()
        ref.source = RepositorySource(snapshotID: UUID(), name: "Product", path: "Sources/Refund.swift", contentHash: String(repeating: "a", count: 64))
        let event = insightEvent(session: UUID(), text: "返金の採用は未決定")
        let request = try InsightRequest(sessionID: event.sessionID, question: "要約", trigger: .manual, events: [event], knowledge: [ref], purpose: .summary)
        let transport = FakeInsightHTTP()
        let payload: [String: Any] = ["text": "採用は未決定です。", "kind": "answerSuggestion", "evidenceIDs": [event.id.uuidString],
                                     "knowledgeIDs": [ref.id.uuidString], "supplement": "実装があります。"]
        transport.chunks = [try geminiSSE(payload: String(decoding: JSONSerialization.data(withJSONObject: payload), as: UTF8.self))]
        let result = try await GeminiInsightClient(key: { "synthetic-key" }, transport: transport).generate(request) { _ in }
        #expect(result.supplement == "実装があります。")
        let body = try #require(transport.requests.first?.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let config = try #require(json["generationConfig"] as? [String: Any])
        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect((schema["required"] as? [String])?.contains("supplement") == true)
        #expect(String(decoding: body, as: UTF8.self).contains("Refund.swift"))
    }
}

@MainActor
final class RepositorySummaryClient: InsightClient {
    var requests: [InsightRequest] = []
    var gate: TestGate?
    var mode = "valid"
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        if let gate { await gate.wait() }
        var result = InsightResult(kind: .answerSuggestion, text: "採用はまだ決まっていません。", evidenceIDs: request.events.map(\.id),
                                   knowledgeIDs: request.knowledge.map(\.id), supplement: request.knowledge.isEmpty ? nil : "資料には返金処理の実装があります。")
        switch mode {
        case "missingSupplement": result.supplement = nil
        case "noCitation": result.knowledgeIDs = []
        case "unknownCitation": result.knowledgeIDs = [UUID()]
        case "emptySupplementWithCitation": result.supplement = ""
        default: break
        }
        if mode == "noSpeech" {
            return InsightResult(kind: .answerSuggestion, text: result.text, evidenceIDs: [], knowledgeIDs: result.knowledgeIDs, supplement: result.supplement)
        }
        return result
    }
}
