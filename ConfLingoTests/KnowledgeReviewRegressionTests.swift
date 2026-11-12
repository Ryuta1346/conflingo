import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct KnowledgeReviewRegressionTests {
    @Test(arguments: [false, true], ["duplicate", "unsupported", "restore", "cancelled"])
    func failedImportKeepsConfirmedTermsAndDrafts(meetingMode: Bool, failure: String) async throws {
        let conference = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: conferenceTestSettings(), client: KnowledgeClient())
        let meeting = libraryMeeting()
        let knowledge = meetingMode ? meeting.knowledge : conference.knowledge
        let terms = meetingMode ? meeting.documentTerms : conference.terms
        let body = Data("# Photon".utf8)
        await knowledge.add(data: body, filename: "terms.md")
        terms.extract(try await knowledge.contents())
        terms.candidates[0].selected = true
        try terms.apply(sourceLanguage: "en", targetLanguage: "ja", manual: [])
        terms.addManual(term: "Unsaved edit", target: "編集中")
        let applied = terms.applied
        let candidates = terms.candidates
        switch failure {
        case "restore":
            let root = temporaryLibrary()
            defer { try? FileManager.default.removeItem(at: root) }
            let archive = try await knowledge.archive(documentID: knowledge.documents[0].id)
            let saved = try await KnowledgeLibraryFiles(directory: root).save(archive, title: "Duplicate")
            await #expect(throws: (any Error).self) { try await knowledge.restore(saved) }
        case "cancelled":
            let task = Task { await knowledge.add(data: Data("Other content".utf8), filename: "other.md") }
            task.cancel()
            await task.value
        default:
            await knowledge.add(data: body, filename: failure == "duplicate" ? "duplicate.md" : "unsupported.pdf")
        }
        #expect(knowledge.documents.count == 1)
        #expect(terms.applied == applied)
        #expect(terms.candidates == candidates)
    }

    @Test(arguments: [false, true])
    func successfulContentChangeStillResetsTerms(meetingMode: Bool) async throws {
        let conference = ConferenceKnowledgeWorkspace(store: SessionStore(), settings: conferenceTestSettings(), client: KnowledgeClient())
        let meeting = libraryMeeting()
        let knowledge = meetingMode ? meeting.knowledge : conference.knowledge
        let terms = meetingMode ? meeting.documentTerms : conference.terms
        await knowledge.add(data: Data("# Photon".utf8), filename: "terms.md")
        terms.addManual(term: "Photon", target: "")
        try terms.apply(sourceLanguage: "en", targetLanguage: nil, manual: [])
        await knowledge.add(data: Data("New content".utf8), filename: "new.md")
        #expect(knowledge.documents.count == 2)
        #expect(terms.applied.isEmpty && terms.candidates.isEmpty)
        terms.addManual(term: "Photon", target: "")
        try terms.apply(sourceLanguage: "en", targetLanguage: nil, manual: [])
        await knowledge.remove(knowledge.documents[0].id)
        #expect(terms.applied.isEmpty && terms.candidates.isEmpty)
    }

    @Test func applyingAnotherLanguagePreservesBothMeetingInputs() async throws {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: KnowledgeClient(),
            credentials: APIKeyCredentials(store: MemoryAPIKeyStore()))
        meeting.microphoneLocaleID = "ja-JP"
        meeting.systemLocaleID = "en-US"
        meeting.recognitionMode = .vocabulary
        meeting.documentTerms.addManual(term: "Photon", target: "")
        try meeting.documentTerms.apply(sourceLanguage: "en-US", targetLanguage: nil, manual: [])
        meeting.documentTerms.candidates[0].selected = false
        meeting.documentTerms.addManual(term: "フォトン", target: "")
        try meeting.documentTerms.apply(sourceLanguage: "ja-JP", targetLanguage: nil, manual: [])
        meeting.consentConfirmed = true
        await meeting.start()
        #expect(fixture.microphone.keywords == ["フォトン"])
        #expect(fixture.system.keywords == ["Photon"])
        await meeting.end()
    }

    @Test func reapplyingALanguageReplacesOnlyThatLanguage() throws {
        let terms = DocumentTerms()
        terms.addManual(term: "Photon", target: "")
        try terms.apply(sourceLanguage: "en-US", targetLanguage: nil, manual: [])
        terms.candidates = []
        terms.addManual(term: "フォトン", target: "")
        try terms.apply(sourceLanguage: "ja-JP", targetLanguage: nil, manual: [])
        terms.candidates = []
        terms.addManual(term: "NewTerm", target: "")
        try terms.apply(sourceLanguage: "en-GB", targetLanguage: nil, manual: [])
        #expect(terms.glossary(sourceLanguage: "en-US", targetLanguage: nil, manual: []).map(\.term) == ["NewTerm"])
        #expect(terms.glossary(sourceLanguage: "ja-JP", targetLanguage: nil, manual: []).map(\.term) == ["フォトン"])
    }

    @Test func completedDocumentAnswerSavesAndReopensWithoutRecording() async throws {
        let store = SessionStore()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: KnowledgeClient())
        await workspace.knowledge.add(data: Data("料金100円です".utf8), filename: "price.md")
        workspace.setQuestionPermission(true)
        await workspace.ask("料金は？")
        #expect(workspace.answers.count == 1)
        let snapshot = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: "ja", support: workspace.snapshot))
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try await SessionFiles(directory: root).save(snapshot)
        let restored = try await SessionFiles(directory: root).load(snapshot.id)
        #expect(restored.snapshot == snapshot)
        #expect(restored.snapshot.markdown.contains(workspace.answers[0].text))
        #expect(restored.snapshot.markdown.contains("price.md"))
        #expect(restored.snapshot.startedAt == nil)
    }

    @Test func emptyOrUnfinishedConferenceCannotBeSaved() throws {
        let store = SessionStore()
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil, support: .init()) == nil)
        let snapshot = SessionSnapshot.conference(.init(id: store.sessionID, title: "Empty", startedAt: nil,
            sourceLanguage: "en", targetLanguage: nil, segments: [], units: [], support: .init()))
        #expect(throws: (any Error).self) { try snapshot.validate() }
        let pending = MeetingInsight(kind: .answerSuggestion, text: "途中", priority: 1, evidenceIDs: [], status: .generating)
        let unfinished = ConferenceSupportSnapshot(answers: [pending])
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil, support: unfinished) == nil)
        let invalid = SessionSnapshot.conference(.init(id: store.sessionID, title: "Unfinished", startedAt: nil,
            sourceLanguage: "en", targetLanguage: nil, segments: [], units: [], support: unfinished))
        #expect(throws: (any Error).self) { try invalid.validate() }
        var complete = pending
        complete.status = .complete
        store.phase = .listening
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil, support: .init(answers: [complete])) == nil)
    }
}
