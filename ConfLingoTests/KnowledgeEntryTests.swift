import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KnowledgeEntryTests {
    @Test func standaloneLibraryImportAndSeparateSessionSelections() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = KnowledgeLibrary(files: KnowledgeLibraryFiles(directory: root))
        let draft = KnowledgeStore()
        await draft.add(data: Data("料金100円".utf8), filename: "料金.md")
        let id = try #require(draft.documents.first?.id)
        #expect(await library.save(from: draft, documentID: id, title: "事前資料"))
        let entry = try #require(library.entries.first)
        let conference = KnowledgeStore()
        let other = KnowledgeStore()
        #expect(await library.attach(entry.id, to: conference))
        #expect(other.documents.isEmpty)
        #expect(!conference.permitted)
        #expect(!(await library.attach(entry.id, to: conference)))
        await library.delete(entry)
        await conference.search("料金")
        #expect(conference.results.count == 1)
    }

    @Test func cancelledSelectionCannotFinishInStoppedSession() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Preloaded")
        let gate = TestGate()
        let library = KnowledgeLibrary(files: files, load: { _ in await gate.wait(); return saved })
        let knowledge = KnowledgeStore()
        let task = Task { await library.attach(saved.id, to: knowledge) }
        await gate.entered.next()
        knowledge.cancelPendingImports()
        gate.release()
        #expect(!(await task.value))
        #expect(knowledge.documents.isEmpty)
    }

    @Test func liveFileImportKeepsBothAudioSourcesRunningAndRevokesConsent() async throws {
        let root = temporaryLibrary()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("live.md")
        try "ライブ資料".write(to: url, atomically: true, encoding: .utf8)
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: KnowledgeClient(),
            credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        meeting.consentConfirmed = true
        await meeting.start()
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        meeting.setAutomaticAI(true)
        meeting.setAutomaticKnowledgeAllowed(true)
        await meeting.importKnowledge(url)
        #expect(meeting.knowledge.documents.count == 1)
        #expect(!meeting.knowledge.permitted)
        #expect(!meeting.ai.automaticKnowledgeEnabled)
        #expect(meeting.phase == .listening)
        #expect(fixture.microphone.inputStops == 0 && fixture.system.inputStops == 0)
        await meeting.end()
        await meeting.importKnowledge(url)
        #expect(meeting.knowledge.documents.count == 1)
    }
}
