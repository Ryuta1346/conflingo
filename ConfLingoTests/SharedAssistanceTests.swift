import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct SharedAssistanceTests {
    @Test func conferenceCombinesSpeechAndDocumentsAndKeepsEvidence() async throws {
        let store = SessionStore()
        let client = KnowledgeClient()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        let id = try #require(store.appendFinal("料金は100円でよいですか？", startTime: 3))
        await workspace.knowledge.add(data: Data("料金は200円です。".utf8), filename: "price.md")
        workspace.setAssistancePermission(true)
        workspace.knowledge.setPermission(true)
        await workspace.assistance.ask("料金は？")
        let request = try #require(client.requests.first)
        #expect(request.events.map(\.id) == [id])
        #expect(request.events.first?.text == "料金は100円でよいですか？")
        #expect(request.knowledge.count == 1)
        #expect(request.purpose == .assistance)
    }

    @Test(arguments: [AudioInputSelection.microphone, .systemAudio, .both])
    func onlySelectedInputsStartAndResume(selection: AudioInputSelection) async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(selection: selection)
        #expect(controller.startedInputs == selection.origins)
        #expect(fixture.microphone.starts == (selection.origins.contains(.microphone) ? 1 : 0))
        #expect(fixture.system.starts == (selection.origins.contains(.systemAudio) ? 1 : 0))
        await controller.stop()
        #expect(controller.phase == .idle)
        await controller.start(selection: selection)
        #expect(controller.startedInputs == selection.origins)
        await controller.stop()
        #expect(fixture.activity.owner == nil)
    }

    @Test func systemOnlyDoesNotAskForDeniedMicrophonePermission() async {
        let fixture = DualFixture()
        fixture.microphonePermission.status = .denied
        let controller = fixture.controller()
        await controller.start(selection: .systemAudio)
        #expect(controller.phase == .listening)
        #expect(fixture.microphonePermission.requests == 0)
        #expect(fixture.microphone.starts == 0)
        await controller.stop()
    }
}

extension SharedAssistanceTests {
    @Test func conferenceCapturesSystemAudioAndPreservesItAfterStop() async throws {
        let fixture = DualFixture()
        let dual = fixture.controller(owner: .conference)
        let controller = SessionController(dualController: dual)
        let store = SessionStore()
        let translation = TranslationCoordinator()
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: .systemAudio)
        try await fixture.system.emit("A system audio sentence.", time: 2)
        await controller.stop(store: store, coordinator: translation)
        #expect(store.phase == .idle)
        #expect(store.segments.map(\.english) == ["A system audio sentence."])
        #expect(store.segments.first?.origin == .systemAudio)
        #expect(store.units.count == 1)
        #expect(fixture.microphone.starts == 0)
    }

    @Test func conferenceSupportWithSpeechAndWebSavesAndExports() throws {
        let segment = TranscriptSegment(id: UUID(), index: 1, english: "Spoken claim", finalizedAt: Date(), startTime: 1)
        let web = WebReference(id: UUID(), url: URL(string: "https://example.com/evidence")!, title: "Source", fetchedAt: Date())
        let answer = MeetingInsight(kind: .risk, text: "Conflict with public source", priority: 2,
            evidenceIDs: [segment.id], webReferences: [web])
        let snapshot = SessionSnapshot.conference(ConferenceSnapshot(id: UUID(), title: "Conference", startedAt: nil,
            sourceLanguage: "en", targetLanguage: nil, segments: [segment], units: [], support: ConferenceSupportSnapshot(answers: [answer])))
        try snapshot.validate()
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.markdown.contains("https://example.com/evidence"))
        #expect(decoded.markdown.contains("Spoken claim"))
    }

    @Test func savedMeetingExportsWebResearchAnswers() throws {
        guard case .meeting(let value, _) = sessionFixture() else { return }
        let web = WebReference(id: UUID(), url: URL(string: "https://example.com/research")!, title: "Source", fetchedAt: Date())
        let answer = MeetingInsight(kind: .answerSuggestion, text: "Web research result", priority: 1,
            evidenceIDs: value.events.map(\.id), webReferences: [web])
        let snapshot = SessionSnapshot.meeting(value, [answer])
        try snapshot.validate()
        #expect(snapshot.markdown.contains("Web research result"))
        #expect(snapshot.markdown.contains("https://example.com/research"))
    }
}

extension SharedAssistanceTests {
    @Test func conferenceAutomaticallySuggestsFromNewSpeechAndDocuments() async throws {
        let client = KnowledgeClient()
        let gate = TestGate()
        client.gate = gate
        let store = SessionStore()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金は200円です。".utf8), filename: "price.md")
        workspace.setAssistancePermission(true)
        workspace.assistance.setAutomatic(true, after: 0)
        workspace.assistance.setAutomaticKnowledge(true)
        store.phase = .listening
        store.appendFinal("料金は100円でよいですか？", startTime: 3)
        await gate.entered.next()
        #expect(client.requests.first?.trigger == .automatic)
        #expect(client.requests.first?.knowledge.count == 1)
        #expect(client.requests.first?.events.count == 1)
        workspace.stop()
        gate.release()
        #expect(workspace.assistance.insights.allSatisfy { $0.status != .complete })
    }

    @Test func resetConferenceClearsAssistanceEvidenceAndPermission() {
        let store = SessionStore()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: KnowledgeClient())
        store.appendFinal("Old session", startTime: 1)
        workspace.setAssistancePermission(true)
        workspace.research.setPermission(true)
        store.reset()
        #expect(workspace.assistanceStore.finals.isEmpty)
        #expect(workspace.assistanceStore.sessionID == store.sessionID)
        #expect(!workspace.assistance.permitted)
        #expect(!workspace.research.permitted)
    }

    @Test func microphoneResumePreservesSupportTimelineAndLanguage() async throws {
        var now = 100.0
        let speech = DualFakeSpeech()
        let store = SessionStore()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: KnowledgeClient())
        let controller = SessionController(speechService: speech, requestPermission: { true }, timeline: MeetingTimeline(now: { now }))
        let translation = TranslationCoordinator()
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"))
        try await speech.emit("first.", time: 1)
        await controller.stop(store: store, coordinator: translation)
        now = 125
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "ja"))
        try await speech.emit("次の発話です。", time: 1)
        await controller.stop(store: store, coordinator: translation)
        #expect(workspace.assistanceStore.finals.map(\.startOffset) == [1, 26])
        #expect(workspace.assistanceStore.finals.map(\.languageCode) == ["en", "ja"])
        #expect(store.segments.map(\.startTime) == [1, 1])
    }

    @Test func meetingCanAskAboutDocumentsBeforeAudioStarts() async {
        let fixture = DualFixture()
        let client = KnowledgeClient()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: client, llmSettings: conferenceTestSettings())
        await meeting.knowledge.add(data: Data("料金200円です。".utf8), filename: "price.md")
        meeting.setAIAllowed(true)
        meeting.setKnowledgeAllowed(true)
        await meeting.askAssistance("料金は？")
        #expect(client.requests.first?.knowledge.count == 1)
        #expect(fixture.microphone.starts == 0 && fixture.system.starts == 0)
    }
}
