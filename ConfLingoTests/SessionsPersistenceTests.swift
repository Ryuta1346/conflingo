import Darwin
import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct SessionsPersistenceTests {
    @Test func explicitSaveSurvivesNewStoreAndUpdateDoesNotDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        #expect(try await files.list().isEmpty)
        let snapshot = sessionFixture()
        let first = try await files.save(snapshot, now: Date(timeIntervalSince1970: 10))
        let reopened = SessionFiles(directory: root)
        #expect(try await reopened.load(snapshot.id).snapshot == snapshot)
        let second = try await reopened.save(snapshot, now: Date(timeIntervalSince1970: 20))
        #expect(second.createdAt == first.createdAt)
        #expect(second.updatedAt == Date(timeIntervalSince1970: 20))
        #expect(try await reopened.list().count == 1)
        try await reopened.delete(snapshot.id)
        #expect(try await files.list().isEmpty)
    }

    @Test func corruptAndFutureFilesDoNotHideValidSessionOrGetOverwritten() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        let snapshot = sessionFixture()
        try await files.save(snapshot)
        let badID = UUID()
        let badURL = root.appendingPathComponent(badID.uuidString + ".json")
        try Data("broken".utf8).write(to: badURL)
        var future = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(snapshot.id.uuidString + ".json"))) as? [String: Any]
        future?["version"] = 999
        let futureData = try JSONSerialization.data(withJSONObject: try #require(future))
        let url = root.appendingPathComponent(snapshot.id.uuidString + ".json")
        try futureData.write(to: url)
        let healthy = sessionFixture(title: "Healthy")
        try await files.save(healthy)
        let entries = try await files.list()
        #expect(entries.count == 3)
        #expect(entries.filter { $0.failure != nil }.count == 2)
        #expect(try await files.load(healthy.id).snapshot == healthy)
        await #expect(throws: (any Error).self) { try await files.save(snapshot) }
        #expect(try Data(contentsOf: url) == futureData)
        #expect(try Data(contentsOf: badURL) == Data("broken".utf8))
    }

    @Test func failedWriteKeepsPreviousSavedVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        let snapshot = sessionFixture()
        let saved = try await files.save(snapshot)
        let failing = SessionFiles(directory: root, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        await #expect(throws: (any Error).self) { try await failing.save(snapshot) }
        #expect(try await files.load(snapshot.id) == saved)
    }

    @Test func conferenceRoundTripPreservesIncompleteTranslationsAndMarkdown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let segment = TranscriptSegment(id: UUID(), index: 1, english: "Hello", finalizedAt: Date(), startTime: 3)
        let unit = TranslationUnit(id: UUID(), index: 1, segmentIDs: [segment.id], english: "Hello", japanese: nil,
                                   translationState: .translating, startTime: 3)
        let snapshot = SessionSnapshot.conference(ConferenceSnapshot(id: UUID(), title: "字幕", startedAt: Date(),
            sourceLanguage: "en-US", targetLanguage: "ja", segments: [segment], units: [unit]))
        let files = SessionFiles(directory: root)
        try await files.save(snapshot)
        let loaded = try await files.load(snapshot.id)
        #expect(loaded.snapshot == snapshot)
        #expect(loaded.snapshot.markdown == snapshot.markdown)
        #expect(loaded.snapshot.markdown.contains("untranslated"))
    }

    @Test func invalidEventOrBrokenReferenceCannotBeSaved() async throws {
        let id = UUID()
        let event = TranscriptEvent(id: UUID(), sessionID: id, origin: .microphone, languageCode: "ja", startOffset: -1,
                                    endOffset: nil, text: "bad", isFinal: true, revision: 1, sourceStartTime: nil)
        let snapshot = SessionSnapshot.meeting(MeetingExportSnapshot(title: "bad", startedAt: nil, microphoneLocale: "ja",
            systemLocale: "en", sessionID: id, events: [event], candidates: [], summary: nil), [])
        #expect(throws: (any Error).self) { try snapshot.validate() }
    }
}

func sessionFixture(title: String = "設計 Review", id: UUID = UUID()) -> SessionSnapshot {
    let event = TranscriptEvent(id: UUID(), sessionID: id, origin: .microphone, languageCode: "ja-JP", startOffset: 1,
                               endOffset: 2, text: "次回に確認します", isFinal: true, revision: 1, sourceStartTime: 1)
    let reference = KnowledgeReference(id: UUID(), documentID: UUID(), title: "Design", importedAt: Date(timeIntervalSince1970: 1),
        startLine: 2, characterOffset: 5, snippet: "Stored excerpt", source: RepositorySource(snapshotID: UUID(), name: "demo",
        path: "Sources/Design.swift", contentHash: String(repeating: "a", count: 64)))
    let card = MeetingInsight(kind: .actionCandidate, text: "確認する", priority: 0, evidenceIDs: [event.id], knowledgeReferences: [reference])
    let candidate = MeetingCandidate(sessionID: id, insight: card, review: .confirmed)
    let summary = MeetingSummary(sessionID: id, answerLanguage: .japanese, sections: [MeetingSummarySection(id: UUID(), text: "確認予定",
        evidenceIDs: [event.id], startOffset: 1, endOffset: 2, supplement: "資料の補足", knowledgeReferences: [reference])])
    return .meeting(MeetingExportSnapshot(title: title, startedAt: Date(timeIntervalSince1970: 1), microphoneLocale: "ja-JP",
        systemLocale: "en-US", sessionID: id, events: [event], candidates: [candidate], summary: summary), [card])
}

extension SessionsPersistenceTests {
    @Test func foreignAndDuplicateIDsAndInvalidTimesAreRejected() throws {
        guard case .meeting(let value, let cards) = sessionFixture() else { return }
        let foreign = MeetingExportSnapshot(title: value.title, startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
            sessionID: UUID(), events: value.events, candidates: value.candidates, summary: value.summary)
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(foreign, cards).validate() }
        let duplicate = MeetingExportSnapshot(title: value.title, startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
            sessionID: value.sessionID, events: value.events + value.events, candidates: [], summary: nil)
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(duplicate, []).validate() }
        let badCard = MeetingInsight(kind: .answerSuggestion, text: "Invalid", priority: 0, evidenceIDs: [UUID()])
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(value, [badCard]).validate() }
        let segment = TranscriptSegment(id: UUID(), index: 1, english: "Bad time", finalizedAt: Date(), startTime: .infinity)
        let badTime = ConferenceSnapshot(id: UUID(), title: "Invalid time", startedAt: nil, sourceLanguage: "en",
                                        targetLanguage: nil, segments: [segment], units: [])
        #expect(throws: (any Error).self) { try SessionSnapshot.conference(badTime).validate() }
    }

    @Test func deletionLeavesExternalMarkdownAndSourceFilesUntouched() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root.appendingPathComponent("sessions"))
        let snapshot = sessionFixture()
        try await files.save(snapshot)
        let external = root.appendingPathComponent("export.md")
        try snapshot.markdown.write(to: external, atomically: true, encoding: .utf8)
        let source = root.appendingPathComponent("source.txt")
        try "Original".write(to: source, atomically: true, encoding: .utf8)
        try await files.delete(snapshot.id)
        #expect(try String(contentsOf: external, encoding: .utf8) == snapshot.markdown)
        #expect(try String(contentsOf: source, encoding: .utf8) == "Original")
    }

    @Test func symbolicLinkIsNotReadAndDeleteDoesNotRemoveItsTarget() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("sessions")
        let files = SessionFiles(directory: directory)
        let snapshot = sessionFixture()
        try await files.save(snapshot)
        let target = directory.appendingPathComponent(snapshot.id.uuidString + ".json")
        let alias = UUID()
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(alias.uuidString + ".json"), withDestinationURL: target)
        #expect(try await files.list().first { $0.id == alias }?.failure != nil)
        await #expect(throws: (any Error).self) { try await files.load(alias) }
        try await files.delete(alias)
        #expect(try await files.load(snapshot.id).snapshot == snapshot)
    }

    @Test func hundredSessionsCanBeListedSearchedAndLoaded() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root)
        var first: UUID?
        for index in 0..<100 {
            guard case .meeting(let value, let cards) = sessionFixture(title: "会議 \(index)") else { return }
            let extra = (2...240).map { offset in
                TranscriptEvent(id: UUID(), sessionID: value.sessionID, origin: .systemAudio, languageCode: "en-US",
                    startOffset: Double(offset), endOffset: Double(offset + 1), text: String(repeating: "Synthetic transcript. ", count: 10),
                    isFinal: true, revision: 1, sourceStartTime: Double(offset))
            }
            let snapshot = SessionSnapshot.meeting(MeetingExportSnapshot(title: value.title, startedAt: value.startedAt,
                microphoneLocale: value.microphoneLocale, systemLocale: value.systemLocale, sessionID: value.sessionID,
                events: value.events + extra, candidates: value.candidates, summary: value.summary), cards)
            try await files.save(snapshot)
            if first == nil { first = snapshot.id }
        }
        var before = rusage()
        getrusage(RUSAGE_SELF, &before)
        let start = ContinuousClock.now
        let entries = try await files.list()
        let duration = start.duration(to: .now)
        #expect(entries.count == 100)
        #expect(entries.filter { $0.title.contains("会議 99") }.count == 1)
        let loadStart = ContinuousClock.now
        let loaded = try await files.load(try #require(first))
        #expect(loaded.snapshot.id == first)
        var after = rusage()
        getrusage(RUSAGE_SELF, &after)
        print("SESSIONS_MEMORY processPeakBefore=\(before.ru_maxrss) processPeakAfter=\(after.ru_maxrss) bytes")
        print("SESSIONS_BENCHMARK list100=\(duration) load240events=\(loadStart.duration(to: .now))")
    }
}
