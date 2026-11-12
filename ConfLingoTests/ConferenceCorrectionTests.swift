import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ConferenceCorrectionTests {
    @Test func correctionKeepsOriginalAndOnlyExplicitAdoptionIsSaved() async throws {
        let store = SessionStore()
        let segment = try #require(store.appendFinal("Photon has a rate limit.", startTime: 1))
        let unit = try #require(store.bufferSegment(segment))
        store.applyTranslation(id: unit.id, japanese: "Photonには制限があります。")
        let client = CorrectionClient()
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("rate limit は 利用上限 です。".utf8), filename: "terms.md")
        await workspace.correct(unitID: unit.id, sourceLanguage: "en", targetLanguage: "ja")
        #expect(client.requests.isEmpty)
        workspace.setCorrectionPermission(true)
        await workspace.correct(unitID: unit.id, sourceLanguage: "en", targetLanguage: "ja")
        let correction = try #require(workspace.corrections.first)
        #expect(store.segments.first?.english == "Photon has a rate limit.")
        #expect(store.units.first?.japanese == "Photonには制限があります。")
        #expect(workspace.snapshot.corrections.isEmpty)
        workspace.adoptCorrection(correction.id, adopted: true)
        #expect(workspace.snapshot.corrections.count == 1)
        let snapshot = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: "ja", support: workspace.snapshot))
        try snapshot.validate()
        let restored = try JSONDecoder().decode(SessionSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.markdown.contains("Photonには利用上限があります。"))
        #expect(restored.markdown.contains("Photonには制限があります。"))
        #expect(TranscriptPresentation.translation(store, corrections: workspace.snapshot.corrections).first?.text.contains("利用上限") == true)
        let changedLanguages = try #require(store.sessionSnapshot(sourceLanguage: "ja", targetLanguage: "en", support: workspace.snapshot))
        try changedLanguages.validate()
        workspace.adoptCorrection(correction.id, adopted: false)
        #expect(workspace.snapshot.corrections.isEmpty)
        #expect(client.requests.first?.events.isEmpty == true)
    }

    @Test(arguments: ["citations", "numbers"])
    func invalidCitationsAndChangedNumbersCannotBeAdopted(reason: String) async throws {
        let store = SessionStore()
        let segment = try #require(store.appendFinal("料金は100円です。", startTime: 0))
        let unit = try #require(store.bufferSegment(segment))
        let client = CorrectionClient()
        client.invalid = reason
        let workspace = ConferenceKnowledgeWorkspace(store: store, settings: conferenceTestSettings(), client: client)
        await workspace.knowledge.add(data: Data("料金100円".utf8), filename: "a.md")
        workspace.setCorrectionPermission(true)
        await workspace.correct(unitID: unit.id, sourceLanguage: "ja", targetLanguage: nil)
        #expect(workspace.corrections.isEmpty)
        #expect(!workspace.message.isEmpty)
    }

    @Test func oldConferenceSnapshotsDecodeWithoutSupport() throws {
        let store = SessionStore()
        _ = store.appendFinal("Old transcript", startTime: 0)
        let snapshot = try #require(store.sessionSnapshot(sourceLanguage: "en", targetLanguage: nil))
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SessionSnapshot.self, from: encoded)
        try decoded.validate()
        if case .conference(let value) = decoded { #expect(value.support == nil) }
        else { Issue.record("Expected Conference") }
    }
}

@MainActor
final class CorrectionClient: InsightClient {
    var requests: [InsightRequest] = []
    var invalid = ""
    func generate(_ request: InsightRequest, update: @escaping @MainActor (String) -> Void) async throws -> InsightResult {
        requests.append(request)
        return InsightResult(kind: .answerSuggestion, text: invalid == "numbers" ? "料金は200円です。" : request.correction?.sourceText ?? "", evidenceIDs: [],
            knowledgeIDs: invalid == "citations" ? [UUID()] : request.knowledge.map(\.id), supplement: "Photonには利用上限があります。")
    }
}
