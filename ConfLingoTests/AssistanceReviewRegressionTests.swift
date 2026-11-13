import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct AssistanceReviewRegressionTests {
    @Test(arguments: [AudioInputSelection.microphone, .systemAudio, .both])
    func conferenceStopFailureIsVisibleUntilSuccessfulRetry(selection: AudioInputSelection) async {
        let fixture = DualFixture()
        let dual = fixture.controller(owner: .conference)
        let controller = SessionController(dualController: dual)
        let store = SessionStore()
        let translation = TranslationCoordinator()
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: selection)
        let failingInput = selection == .microphone ? fixture.microphone : fixture.system
        failingInput.stopError = .stop
        await controller.stop(store: store, coordinator: translation)
        #expect(dual.lastError != nil)
        #expect(controller.lastError == dual.lastError)
        #expect(store.phase == .stopping)
        #expect(fixture.activity.owner == .conference)
        await controller.start(store: store, coordinator: translation, locale: Locale(identifier: "en"), selection: selection)
        #expect(failingInput.starts == 1)
        failingInput.stopError = nil
        await controller.stop(store: store, coordinator: translation)
        #expect(controller.lastError == nil)
        #expect(store.phase == .idle)
        #expect(fixture.activity.owner == nil)
    }

    @Test(arguments: [false, true])
    func preparationAnswersSaveReloadAndExportWithoutAudio(web: Bool) async throws {
        let meeting = try await answeredMeeting(web: web)
        #expect(meeting.page == .setup)
        #expect(meeting.store.finals.isEmpty)
        let answer = try #require(meeting.completedAssistance.first)
        let snapshot = try #require(meeting.sessionSnapshot)
        try snapshot.validate()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        let library = SessionsLibrary(files: files)
        await meeting.saveSession(to: library)
        let saved = try await files.load(snapshot.id)
        #expect(saved.snapshot == snapshot)
        let export = try #require(meeting.exportSnapshot)
        let output = root.appendingPathComponent("answer.md")
        meeting.export.save(export, to: output)
        let markdown = try String(contentsOf: output, encoding: .utf8)
        if web {
            #expect(markdown.contains("Combined answer"))
            #expect(markdown.contains("https://example.com/source"))
        } else {
            #expect(markdown.contains(answer.text))
            #expect(markdown.contains("price.md"))
        }
        await meeting.end()
        #expect(meeting.sessionSnapshot == snapshot)
        meeting.requestDiscard()
        #expect(meeting.showsDiscardConfirmation)
        #expect(meeting.completedAssistance.first?.id == answer.id)
    }

    @Test func emptyIncompleteAndUnknownEvidenceRemainUnsavable() async throws {
        let meeting = MeetingWorkspace(controller: DualFixture().controller(), llmSettings: conferenceTestSettings())
        #expect(meeting.sessionSnapshot == nil)
        meeting.insights = [MeetingInsight(kind: .answerSuggestion, text: "Partial", priority: 1, evidenceIDs: [], status: .generating)]
        #expect(meeting.sessionSnapshot == nil)
        await meeting.end()
        let empty = MeetingExportSnapshot(title: "Empty", startedAt: nil, microphoneLocale: "en", systemLocale: "en",
            sessionID: meeting.store.sessionID, events: [], candidates: [], summary: nil)
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(empty, []).validate() }
        let invalid = MeetingInsight(kind: .answerSuggestion, text: "Unknown speech", priority: 1, evidenceIDs: [UUID()])
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(empty, [invalid]).validate() }
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(empty, meeting.insights).validate() }
    }

    @Test func preparationShowsAnswerCitationAndSaveActions() async throws {
        let meeting = try await answeredMeeting(web: false)
        meeting.insights[0].text = "Preparation answer marker"
        let labels = try await screenText(meeting)
        #expect(labels.contains("Preparation answer marker"))
        #expect(labels.contains("price.md"))
        #expect(labels.contains("このMacに保存"))
        #expect(labels.contains("Markdownを書き出す"))
    }

    @Test func reviewShowsCompletedResearchAndSourcesWithoutSendingControls() async throws {
        let meeting = try await answeredMeeting(web: true)
        await meeting.end()
        let labels = try await screenText(meeting)
        #expect(labels.contains("Combined answer"))
        #expect(labels.contains("Public source"))
        #expect(!labels.contains("この提案をWebで調べる"))
    }

    private func answeredMeeting(web: Bool) async throws -> MeetingWorkspace {
        let fixture = DualFixture()
        let meeting = MeetingWorkspace(controller: fixture.controller(), insightClient: KnowledgeClient(),
            llmSettings: conferenceTestSettings(), researchClient: ResearchClient())
        if web {
            meeting.research.setPermission(true)
            await meeting.research.run(question: "Public facts", language: .english)
        } else {
            await meeting.knowledge.add(data: Data("料金100円です。".utf8), filename: "price.md")
            meeting.setAIAllowed(true)
            meeting.setKnowledgeAllowed(true)
            await meeting.askAssistance("料金は？")
        }
        #expect(fixture.microphone.starts == 0 && fixture.system.starts == 0)
        return meeting
    }

    private func screenText(_ meeting: MeetingWorkspace) async throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SessionsLibrary(files: SessionFiles(directory: root))
        let host = NSHostingView(rootView: MeetingWorkspaceView(meeting: meeting, fontSize: .constant(16), compact: {}, sessions: library))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        let enhancedUI = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previous = NSApp.accessibilityAttributeValue(enhancedUI)
        NSApp.accessibilitySetValue(true, forAttribute: enhancedUI)
        window.orderFront(nil)
        defer {
            window.close()
            NSApp.accessibilitySetValue(previous ?? false, forAttribute: enhancedUI)
        }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        let text = accessibilityText(host)
        #expect(text.contains("Meeting"), "The accessibility tree must include the Meeting heading")
        return text
    }

    private func accessibilityText(_ element: Any) -> String {
        guard let object = element as? NSObject else { return "" }
        // SwiftUIの要素はNSAccessibilityProtocolへの準拠を公開しないため、公開セレクターを読む。
        func value(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        let own = ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"].compactMap { value($0) as? String }
        let children = value("accessibilityChildren") as? [Any] ?? []
        return (own + children.map { accessibilityText($0) }).joined(separator: "\n")
    }
}
