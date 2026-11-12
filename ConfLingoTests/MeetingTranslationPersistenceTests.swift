import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct MeetingTranslationPersistenceTests {
    @Test func completedTranslationsSurviveSaveReloadAndMarkdownWhileLegacyDataStillLoads() async throws {
        guard case .meeting(var snapshot, let cards) = sessionFixture() else { return }
        let event = try #require(snapshot.events.first)
        let originalData = try JSONEncoder().encode(snapshot)
        let oldJSON = try #require(JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        #expect(oldJSON["translations"] == nil)
        #expect(try JSONDecoder().decode(MeetingExportSnapshot.self, from: originalData).translations == nil)
        snapshot.translations = [MeetingTranslation(id: event.id, sourceLanguage: event.languageCode,
                                                   targetLanguage: "en", text: "We will check next time. <script>")]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try await SessionFiles(directory: root).save(.meeting(snapshot, cards))
        let loaded = try await SessionFiles(directory: root).load(snapshot.sessionID)
        #expect(loaded.snapshot == .meeting(snapshot, cards))
        #expect(loaded.snapshot.markdown.contains(event.text))
        #expect(loaded.snapshot.markdown.contains("We will check next time. &lt;script&gt;"))
        #expect(!loaded.snapshot.markdown.contains("<script>"))
    }

    @Test func rejectsDuplicateOrOrphanedTranslationsAndWrongSourceLanguage() throws {
        guard case .meeting(var snapshot, let cards) = sessionFixture() else { return }
        let event = try #require(snapshot.events.first)
        let valid = MeetingTranslation(id: event.id, sourceLanguage: event.languageCode, targetLanguage: "en", text: "Translated")
        snapshot.translations = [valid, valid]
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(snapshot, cards).validate() }
        snapshot.translations = [MeetingTranslation(id: UUID(), sourceLanguage: "ja", targetLanguage: "en", text: "Orphan")]
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(snapshot, cards).validate() }
        snapshot.translations = [MeetingTranslation(id: event.id, sourceLanguage: "fr", targetLanguage: "en", text: "Wrong source")]
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(snapshot, cards).validate() }
        snapshot.translations = [MeetingTranslation(id: event.id, sourceLanguage: event.languageCode, targetLanguage: "en", text: " ")]
        #expect(throws: (any Error).self) { try SessionSnapshot.meeting(snapshot, cards).validate() }
    }

    @MainActor
    @Test func arrivingTranslationInvalidatesPreviouslyExportedSnapshot() throws {
        guard case .meeting(var snapshot, _) = sessionFixture() else { return }
        let event = try #require(snapshot.events.first)
        let export = MeetingExportState()
        export.save(snapshot, to: URL(fileURLWithPath: "/private/tmp/meeting-translation-test.md")) { _, _ in }
        #expect(export.matches(snapshot))
        snapshot.translations = [MeetingTranslation(id: event.id, sourceLanguage: event.languageCode, targetLanguage: "en", text: "Translated")]
        #expect(!export.matches(snapshot))
    }
}
