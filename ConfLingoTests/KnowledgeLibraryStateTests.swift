import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KnowledgeLibraryStateTests {
    @Test func savingTwiceCreatesOneEntryAndNextMeetingNeedsFreshConsent() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = KnowledgeLibrary(files: KnowledgeLibraryFiles(directory: root))
        let meeting = libraryMeeting()
        await meeting.knowledge.add(data: Data("料金100円".utf8), filename: "price.md")
        let doc = try #require(meeting.knowledge.documents.first)
        #expect(await library.save(from: meeting, documentID: doc.id, title: "Price 資料"))
        #expect(await library.save(from: meeting, documentID: doc.id, title: "Price 資料"))
        #expect(library.entries.count == 1)
        let next = libraryMeeting()
        next.setAIAllowed(true)
        next.setKnowledgeAllowed(true)
        next.setAutomaticAI(true)
        next.setAutomaticKnowledgeAllowed(true)
        #expect(await library.attach(library.entries[0].id, to: next))
        #expect(!next.knowledge.permitted)
        #expect(!next.ai.automaticKnowledgeEnabled)
        #expect(next.knowledge.documents.first?.importedAt == doc.importedAt)
        #expect(!(await library.attach(library.entries[0].id, to: next)))
        library.query = "price"
        #expect(library.filtered.count == 1)
        library.query = "missing"
        #expect(library.filtered.isEmpty)
    }

    @Test func savingOldMeetingCannotOverwriteNewerLibraryRevision() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Original")
        let library = KnowledgeLibrary(files: files)
        let first = libraryMeeting()
        let second = libraryMeeting()
        #expect(await library.attach(saved.id, to: first))
        #expect(await library.attach(saved.id, to: second))
        #expect(await library.save(from: first, documentID: first.knowledge.documents[0].id, title: "New name"))
        #expect(!(await library.save(from: second, documentID: second.knowledge.documents[0].id, title: "Old name")))
        #expect(try await files.load(saved.id).title == "New name")
    }

    @Test func libraryDeletionAndMeetingDiscardHaveIndependentLifetimes() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Price")
        let library = KnowledgeLibrary(files: files)
        await library.reload()
        let meeting = libraryMeeting()
        #expect(await library.attach(saved.id, to: meeting))
        await library.delete(try #require(library.entries.first))
        await meeting.knowledge.search("料金")
        #expect(meeting.knowledge.results.count == 1)
        #expect(library.entries.isEmpty)
        #expect(await library.save(from: meeting, documentID: meeting.knowledge.documents[0].id, title: "Saved again"))
        meeting.requestDiscard()
        meeting.confirmDiscard()
        #expect(meeting.knowledge.documents.isEmpty)
        #expect(try await files.list().count == 1)
    }

    @Test func delayedLoadCannotAttachToResetMeeting() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Price")
        let gate = TestGate()
        let library = KnowledgeLibrary(files: files, load: { _ in await gate.wait(); return saved })
        let meeting = libraryMeeting()
        let pending = Task { await library.attach(saved.id, to: meeting) }
        await gate.entered.next()
        #expect(!meeting.canStart)
        #expect(!meeting.canDiscard)
        meeting.knowledge.reset()
        gate.release()
        #expect(!(await pending.value))
        #expect(meeting.knowledge.documents.isEmpty)
        #expect(!meeting.isUsingLibrary)
    }

    @Test func failedAttachmentDoesNotChangeExistingDocumentsOrPermission() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive("料金100円"), title: "Duplicate")
        let library = KnowledgeLibrary(files: files)
        let meeting = libraryMeeting()
        await meeting.knowledge.add(data: Data("料金100円".utf8), filename: "existing.md")
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        #expect(!(await library.attach(saved.id, to: meeting)))
        #expect(meeting.knowledge.documents.count == 1)
        #expect(meeting.knowledge.permitted)
        #expect(library.error != nil)
    }

    @Test(arguments: ["manual", "automatic", "summary"])
    func restoredDocumentsFeedExistingAIFlowsWithPreservedCitations(flow: String) async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive("refundPayment は返金処理です。"), title: "返金資料")
        let client = RepositorySummaryClient()
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), insightClient: client,
            credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        let library = KnowledgeLibrary(files: files)
        #expect(await library.attach(saved.id, to: meeting))
        #expect(client.requests.isEmpty)
        #expect(meeting.phase == .idle)
        meeting.ai.resume()
        meeting.setAIAllowed(true)
        let event = insightEvent(session: meeting.store.sessionID, text: "refundPayment を採用できますか？", offset: 1)
        meeting.store.receive(event)
        switch flow {
        case "manual":
            meeting.setKnowledgeAllowed(true)
            await meeting.ai.ask("refundPayment は？")
            #expect(meeting.insights.last?.knowledgeReferences.count == 1)
        case "automatic":
            meeting.setAutomaticAI(true)
            meeting.setAutomaticKnowledgeAllowed(true)
            await meeting.ai.receive(event)?.value
            #expect(meeting.insights.last?.knowledgeReferences.count == 1)
        default:
            await meeting.end()
            let plan = try await meeting.summaryPlan(includingKnowledge: true)
            await meeting.generateSummary(plan, consent: true)
            #expect(meeting.summary.completed?.sections.first?.knowledgeReferences.count == 1)
            #expect(meeting.exportSnapshot?.markdown.contains("refundPayment") == true)
        }
        let reference = try #require(client.requests.last?.knowledge.first)
        #expect(reference.importedAt == saved.content.documents[0].document.importedAt)
        #expect(reference.snippet == saved.content.documents[0].body)
    }

    @Test func libraryNavigationRequiresStoppingAudio() async {
        let navigation = ConferenceNavigation(destination: .meeting)
        navigation.request(.library, phase: .listening)
        #expect(navigation.destination == .meeting)
        #expect(navigation.showsStopConfirmation)
        navigation.cancelNavigation()
        #expect(navigation.destination == .meeting)
        navigation.request(.library, phase: .idle)
        #expect(navigation.destination == .library)
    }

    @Test func activeMeetingCannotSaveOrAttach() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Price")
        let library = KnowledgeLibrary(files: files)
        let meeting = libraryMeeting()
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(!(await library.attach(saved.id, to: meeting)))
        #expect(!(await library.save(from: meeting, documentID: nil, title: "Invalid")))
        await meeting.end()
    }
}

@MainActor
func libraryMeeting() -> MeetingWorkspace {
    MeetingWorkspace(controller: DualFixture().controller(), insightClient: KnowledgeClient(),
                     credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
}
