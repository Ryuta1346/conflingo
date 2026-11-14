import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MeetingTermProtectionTests {
    @Test func protectsSelectedTermsForEachInputWithoutUsingUnconfirmedTranslations() async throws {
        let client = TermTranslationClient()
        let meeting = workspace(client)
        let terms = meeting.documentTerms
        terms.addManual(term: "Photon", target: "誤った固定訳")
        terms.addManual(term: "Photon SDK", target: "未確認の訳")
        try terms.apply(sourceLanguage: "en", targetLanguage: nil, manual: [])
        terms.selectCandidates(sourceLanguage: "ja")
        terms.addManual(term: "フォトン", target: "WRONG")
        try terms.apply(sourceLanguage: "ja", targetLanguage: nil, manual: [])
        terms.addManual(term: "未採用", target: "unused")
        let english = translationEvent(meeting.store.sessionID, text: "PHOTON Photon SDK PhotonSDK Photon")
        let japanese = translationEvent(meeting.store.sessionID, origin: .microphone, text: "フォトンとフォトン 未採用", language: "ja-JP")
        meeting.store.receive(english)
        meeting.store.receive(japanese)
        await settleTranslations(meeting.translations)
        let requests = await client.requests
        #expect(requests.first { $0.event.id == english.id }?.text == "⟦0⟧ ⟦1⟧ PhotonSDK ⟦2⟧")
        #expect(requests.first { $0.event.id == japanese.id }?.text == "⟦0⟧と⟦1⟧ 未採用")
        #expect(meeting.translations.entries[english.id]?.translation?.text == "translated PHOTON Photon SDK PhotonSDK Photon")
        #expect(meeting.translations.entries[japanese.id]?.translation?.text == "translated フォトンとフォトン 未採用")
        #expect(meeting.store.finals.map(\.text) == [english.text, japanese.text])
        #expect(!meeting.ai.permitted)
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func freezesInFlightTermsButUsesNewTermsForQueuedRequestsAndAfterClear() async throws {
        let gate = TestGate()
        let client = TermTranslationClient(gate: gate)
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let first = translationEvent(meeting.store.sessionID, text: "Photon Alpha")
        let second = translationEvent(meeting.store.sessionID, text: "Photon Alpha")
        meeting.store.receive(first)
        await gate.entered.next()
        meeting.store.receive(second)
        meeting.documentTerms.clear(sourceLanguage: "en")
        try apply("Alpha", to: meeting)
        gate.release()
        await settleTranslations(meeting.translations)
        #expect(await client.requests.map(\.text) == ["⟦0⟧ Alpha", "Photon ⟦0⟧"])
        #expect(meeting.translations.entries[first.id]?.translation?.text == "translated Photon Alpha")
        meeting.documentTerms.clear(sourceLanguage: "en")
        meeting.store.receive(translationEvent(meeting.store.sessionID, text: "Photon Alpha"))
        await settleTranslations(meeting.translations)
        #expect(await client.requests.last?.text == "Photon Alpha")
        #expect(meeting.translations.entries[first.id]?.translation?.text == "translated Photon Alpha")
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func documentReplacementClearsProtectionForSubsequentSpeech() async throws {
        let client = TermTranslationClient()
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        meeting.store.receive(translationEvent(meeting.store.sessionID, text: "Photon"))
        await settleTranslations(meeting.translations)
        await meeting.knowledge.add(data: Data("new content".utf8), filename: "new.md")
        #expect(meeting.documentTerms.applied.isEmpty)
        meeting.store.receive(translationEvent(meeting.store.sessionID, text: "Photon"))
        await settleTranslations(meeting.translations)
        #expect(await client.requests.map(\.text) == ["⟦0⟧", "Photon"])
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func tolerantRestorationNeedsNoFallback() async throws {
        let client = TermTranslationClient(outputs: [.text("translated [[ ０ ]] ")])
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let event = translationEvent(meeting.store.sessionID, text: "Photon")
        meeting.store.receive(event)
        await settleTranslations(meeting.translations)
        #expect(meeting.translations.entries[event.id]?.translation?.text == "translated Photon ")
        #expect(await client.requests.count == 1)
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func missingTokenRetranslatesOriginalOnceUsingTheSameClient() async throws {
        let gate = TestGate()
        let client = TermTranslationClient(outputs: [.text("token lost"), .text("フォールバック訳")], gate: gate)
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let event = translationEvent(meeting.store.sessionID, text: "Photon")
        meeting.store.receive(event)
        await gate.entered.next()
        meeting.documentTerms.clear(sourceLanguage: "en")
        gate.release()
        await settleTranslations(meeting.translations)
        #expect(await client.requests.map(\.text) == ["⟦0⟧", "Photon"])
        #expect(meeting.translations.entries[event.id]?.translation?.text == "フォールバック訳")
        #expect(meeting.translations.completed.count == 1)
        meeting.translations.reset(sessionID: UUID())
    }

    @Test(arguments: [TermTranslationClient.Output.failure, .text("   ")])
    func fallbackFailureDoesNotPublishIntermediateTextAndLaterSpeechContinues(output: TermTranslationClient.Output) async throws {
        let client = TermTranslationClient(outputs: [.text("unrecoverable ⟦?⟧"), output, .text("next result")])
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let failed = translationEvent(meeting.store.sessionID, text: "Photon")
        meeting.store.receive(failed)
        await settleTranslations(meeting.translations)
        #expect(meeting.translations.entries[failed.id]?.translation == nil)
        guard case .failed = meeting.translations.entries[failed.id]?.state else {
            Issue.record("An unusable fallback must leave a retryable failure")
            meeting.translations.reset(sessionID: UUID())
            return
        }
        meeting.store.receive(translationEvent(meeting.store.sessionID, text: "next"))
        await settleTranslations(meeting.translations)
        #expect(meeting.translations.completed.map(\.text) == ["next result"])
        #expect(await client.requests.count == 3)
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func cancellationDoesNotStartFallbackOrPublishLateTranslation() async throws {
        let gate = TestGate()
        let client = TermTranslationClient(outputs: [.text("token lost")], gate: gate)
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        meeting.store.receive(translationEvent(meeting.store.sessionID, text: "Photon"))
        await gate.entered.next()
        let task = try #require(meeting.translations.lanes.first?.task)
        meeting.translations.reset(sessionID: UUID())
        gate.release()
        await task.value
        #expect(await client.requests.count == 1)
        #expect(meeting.translations.completed.isEmpty)
    }

    @Test func individualRetryUsesCurrentTermsAndRetainsOriginalEvent() async throws {
        let client = TermTranslationClient(outputs: [.failure])
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let event = translationEvent(meeting.store.sessionID, text: "Photon Alpha")
        meeting.store.receive(event)
        await settleTranslations(meeting.translations)
        meeting.documentTerms.clear(sourceLanguage: "en")
        try apply("Alpha", to: meeting)
        meeting.translations.retry(event.id)
        await settleTranslations(meeting.translations)
        #expect(await client.requests.map(\.text) == ["⟦0⟧ Alpha", "Photon ⟦0⟧"])
        #expect(meeting.translations.entries[event.id]?.request.event == event)
        #expect(meeting.translations.entries[event.id]?.translation?.text == "translated Photon Alpha")
        meeting.translations.reset(sessionID: UUID())
    }

    @Test func restoredTranslationSurvivesSaveReloadAndMarkdown() async throws {
        let client = TermTranslationClient()
        let meeting = workspace(client)
        try apply("Photon", to: meeting)
        let event = translationEvent(meeting.store.sessionID, text: "Photon")
        meeting.store.receive(event)
        await meeting.end()
        await settleTranslations(meeting.translations)
        let snapshot = try #require(meeting.exportSnapshot)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await SessionFiles(directory: root).save(.meeting(snapshot, []))
        let restored = try await SessionFiles(directory: root).load(snapshot.sessionID)
        #expect(restored.snapshot == .meeting(snapshot, []))
        #expect(restored.snapshot.markdown.contains("translated Photon"))
        #expect(!restored.snapshot.markdown.contains("⟦"))
        #expect(await client.requests.first?.text == "⟦0⟧")
        meeting.translations.reset(sessionID: UUID())
    }

    private func workspace(_ client: TermTranslationClient) -> MeetingWorkspace {
        let fixture = DualFixture()
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let meeting = MeetingWorkspace(controller: fixture.controller(), defaults: defaults,
            translationClientFactory: { _, _ in client }, prepareTranslationModels: false)
        meeting.mode = .translation
        return meeting
    }

    private func apply(_ term: String, to meeting: MeetingWorkspace) throws {
        meeting.documentTerms.addManual(term: term, target: "")
        try meeting.documentTerms.apply(sourceLanguage: "en", targetLanguage: nil, manual: [])
    }
}

actor TermTranslationClient: MeetingTranslating {
    enum Output: Sendable { case text(String), failure }
    private(set) var requests: [MeetingTranslationRequest] = []
    private var outputs: [Output]
    private let gate: TestGate?

    init(outputs: [Output] = [], gate: TestGate? = nil) { self.outputs = outputs; self.gate = gate }

    func run(_ ids: AsyncStream<UUID>, source: String, target: String,
             begin: @escaping MeetingTranslationBegin, complete: @escaping MeetingTranslationComplete) async {
        await processMeetingTranslations(ids, begin: begin, complete: complete) { request in
            self.requests.append(request)
            if self.requests.count == 1, let gate = self.gate { await gate.wait() }
            let output = self.outputs.isEmpty ? .text("translated \(request.text)") : self.outputs.removeFirst()
            switch output {
            case .text(let value): return value
            case .failure: throw CocoaError(.fileReadUnknown)
            }
        }
    }
}
