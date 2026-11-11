import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SessionsStateTests {
    @Test func librarySearchRecentReadAndDeletePreserveCurrentMeeting() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SessionsLibrary(files: SessionFiles(directory: root))
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        await MeetingPreview.prepare(meeting, scenario: "live")
        let current = meeting.store.finals
        await meeting.end()
        for index in 0..<6 { await library.save(sessionFixture(title: index == 0 ? "設計 Review" : "会議 \(index)")) }
        #expect(library.recent.count == 5)
        library.query = "review"
        let entry = try #require(library.filtered.first)
        #expect(library.filtered.count == 1)
        await library.open(entry.id)
        #expect(library.selected?.id == entry.id)
        #expect(meeting.store.finals == current)
        #expect(meeting.phase == .idle)
        #expect(!meeting.ai.permitted)
        library.requestDelete(entry)
        library.cancelDelete()
        #expect(library.entries.count == 6)
        library.requestDelete(entry)
        await library.confirmDelete()
        #expect(library.entries.count == 5)
        #expect(library.selected == nil)
        #expect(library.filtered.isEmpty)
    }

    @Test func completedMeetingSnapshotOmitsPartialCardsAndDetectsLaterChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SessionsLibrary(files: SessionFiles(directory: root))
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        await MeetingPreview.prepare(meeting, scenario: "live")
        #expect(meeting.sessionSnapshot == nil)
        await meeting.end()
        meeting.insights.append(MeetingInsight(kind: .answerSuggestion, text: "unfinished", priority: 0, evidenceIDs: [], status: .generating))
        let snapshot = try #require(meeting.sessionSnapshot)
        if case .meeting(_, let cards) = snapshot { #expect(cards.allSatisfy { $0.status == .complete }) }
        await library.save(snapshot)
        #expect(library.matches(snapshot))
        meeting.name = "変更後"
        #expect(!library.matches(try #require(meeting.sessionSnapshot)))
        meeting.isSavingSession = true
        meeting.requestDiscard()
        #expect(!meeting.showsDiscardConfirmation)
        meeting.isSavingSession = false
        #expect(try await SessionFiles(directory: root).load(snapshot.id).snapshot == snapshot)
    }

    @Test func conferenceIdentitySurvivesPauseAndChangesOnReset() throws {
        let store = SessionStore()
        store.appendFinal("Hello")
        let snapshot = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil))
        store.phase = .listening
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil) == nil)
        store.phase = .idle
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil)?.id == snapshot.id)
        store.reset()
        store.appendFinal("New session")
        #expect(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil)?.id != snapshot.id)
    }

    @Test func deleteFailureKeepsListAndSavedSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root, remove: { _ in throw CocoaError(.fileWriteNoPermission) })
        let library = SessionsLibrary(files: files)
        let snapshot = sessionFixture()
        await library.save(snapshot)
        library.requestDelete(try #require(library.entries.first))
        await library.confirmDelete()
        #expect(library.entries.count == 1)
        #expect(library.matches(snapshot))
        #expect(library.error != nil)
    }
}

extension SessionsStateTests {
    @Test func saveFailureNeverMarksNewSnapshotSaved() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = SessionFiles(directory: root, write: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let library = SessionsLibrary(files: files)
        let snapshot = sessionFixture()
        await library.save(snapshot)
        #expect(!library.matches(snapshot))
        #expect(library.entries.isEmpty)
        #expect(!library.isBusy)
        #expect(library.error != nil)
    }

    @Test func deleteConfirmedEntryWorksAfterAlertDismissalAndCanBeExplicitlySavedAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SessionsLibrary(files: SessionFiles(directory: root))
        let snapshot = sessionFixture()
        await library.save(snapshot)
        let entry = try #require(library.entries.first)
        library.requestDelete(entry)
        library.cancelDelete()
        await library.confirmDelete(entry)
        #expect(!library.matches(snapshot))
        #expect(library.entries.isEmpty)
        await library.save(snapshot)
        #expect(library.entries.count == 1)
        #expect(library.matches(snapshot))
    }

    @Test func conferenceLateTranslationRequiresExplicitResaveAndUnknownDateStaysUnknown() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = SessionsLibrary(files: SessionFiles(directory: root))
        let store = SessionStore()
        let segment = try #require(store.appendFinal("Hello."))
        let unit = try #require(store.bufferSegment(segment))
        let snapshot = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: "ja"))
        #expect(snapshot.markdown.contains("Date: 未取得"))
        await library.save(snapshot)
        store.applyTranslation(id: unit.id, japanese: "こんにちは。")
        let updated = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: "ja"))
        #expect(!library.matches(updated))
        #expect(library.matches(snapshot))
        await library.save(updated)
        #expect(library.matches(updated))
        #expect(library.entries.count == 1)
    }
}

extension SessionsStateTests {
    @Test func delayedSaveKeepsItsOwnSnapshotAndBlocksDuplicateOperations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0)
        let signal = AsyncStream<Void>.makeStream()
        let files = SessionFiles(directory: root, write: { data, url in
            signal.continuation.yield(())
            gate.wait()
            try data.write(to: url, options: .atomic)
        })
        let library = SessionsLibrary(files: files)
        let meeting = MeetingPreview.make(activity: AudioInputUse())
        await MeetingPreview.prepare(meeting, scenario: "review")
        let before = try #require(meeting.sessionSnapshot)
        let saving = Task { await meeting.saveSession(to: library) }
        var iterator = signal.stream.makeAsyncIterator()
        await iterator.next()
        #expect(meeting.isSavingSession)
        #expect(library.isBusy)
        meeting.requestDiscard()
        #expect(!meeting.showsDiscardConfirmation)
        await library.save(sessionFixture(title: "Must not save"))
        meeting.name = "保存中の変更"
        gate.signal()
        await saving.value
        #expect(!meeting.isSavingSession)
        #expect(library.entries.count == 1)
        #expect(library.matches(before))
        #expect(!library.matches(try #require(meeting.sessionSnapshot)))
        #expect(try await files.load(before.id).snapshot == before)
    }
}
