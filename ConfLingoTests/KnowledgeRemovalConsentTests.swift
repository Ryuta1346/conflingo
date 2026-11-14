import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KnowledgeRemovalConsentTests {
    @Test(arguments: [false, true])
    func cancelledRemovalKeepsDocumentsAndBothPermissions(repository: Bool) async throws {
        let meeting = libraryMeeting()
        meeting.consentConfirmed = true
        await meeting.start()
        let source = try RepositoryFixture()
        defer { source.remove() }
        if repository {
            try source.write("app.swift", "// existing")
            let scan = try await RepositoryImporter.scan(source.root)
            await meeting.knowledge.importRepository(scan, selected: ["app.swift"])
        } else {
            await meeting.knowledge.add(data: Data("existing".utf8), filename: "existing.md")
        }
        let document = try #require(meeting.knowledge.documents.first)
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        meeting.setAutomaticAI(true)
        meeting.setAutomaticKnowledgeAllowed(true)
        let removal = Task {
            if repository { await meeting.knowledge.removeRepository() }
            else { await meeting.knowledge.remove(document.id) }
        }
        removal.cancel()
        await removal.value
        #expect(meeting.knowledge.documents == [document])
        #expect(meeting.knowledge.permitted && meeting.ai.automaticKnowledgeEnabled)
        #expect(meeting.phase == .listening)
        await meeting.end()
    }

    @Test(arguments: [false, true])
    func removalRevokesBothPermissionsAndKeepsAudioAndCitations(repository: Bool) async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: KnowledgeClient(),
            credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        await meeting.knowledge.add(data: Data("remaining material".utf8), filename: "remaining.md")
        let source = try RepositoryFixture()
        defer { source.remove() }
        if repository {
            try source.write("app.swift", "// removed needle")
            let scan = try await RepositoryImporter.scan(source.root)
            await meeting.knowledge.importRepository(scan, selected: ["app.swift"])
        } else {
            await meeting.knowledge.add(data: Data("removed needle".utf8), filename: "removed.md")
        }
        await meeting.knowledge.search("needle")
        let reference = try #require(meeting.knowledge.results.first)
        let answer = MeetingInsight(kind: .answerSuggestion, text: "Saved citation", priority: 1,
            evidenceIDs: [], knowledgeReferences: [reference])
        meeting.insights = [answer]
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        meeting.setAutomaticAI(true)
        meeting.setAutomaticKnowledgeAllowed(true)
        #expect(meeting.knowledge.permitted && meeting.ai.automaticKnowledgeEnabled)
        if repository { await meeting.knowledge.removeRepository() }
        else { await meeting.knowledge.remove(reference.documentID) }
        #expect(meeting.knowledge.documents.map(\.title) == ["remaining.md"])
        #expect(!meeting.knowledge.permitted && !meeting.ai.automaticKnowledgeEnabled)
        #expect(meeting.insights.contains { $0.id == answer.id && $0.knowledgeReferences == [reference] })
        #expect(meeting.phase == .listening)
        #expect(fixture.microphone.inputStops == 0 && fixture.system.inputStops == 0)
        await meeting.end()
    }

    @Test func missingRemovalAndFailedImportKeepContentAndConsent() async {
        let meeting = libraryMeeting()
        meeting.consentConfirmed = true
        await meeting.start()
        await meeting.knowledge.add(data: Data("existing".utf8), filename: "existing.md")
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        meeting.setAutomaticAI(true)
        meeting.setAutomaticKnowledgeAllowed(true)
        #expect(meeting.knowledge.permitted && meeting.ai.automaticKnowledgeEnabled)
        let documents = meeting.knowledge.documents
        await meeting.knowledge.remove(UUID())
        await meeting.knowledge.removeRepository()
        await meeting.knowledge.add(data: Data("invalid".utf8), filename: "unsupported.pdf")
        #expect(meeting.knowledge.documents == documents)
        #expect(meeting.knowledge.permitted && meeting.ai.automaticKnowledgeEnabled)
        await meeting.end()
    }
}
