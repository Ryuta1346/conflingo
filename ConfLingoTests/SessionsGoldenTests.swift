import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct SessionsGoldenTests {
    private typealias Fixture = PersistenceGoldenFixture

    @Test(arguments: Fixture.sessionNames)
    func historicalV1LoadsListsAndResavesWithoutLosingFields(name: String) async throws {
        let data = try Fixture.data(name)
        let root = try Fixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try Fixture.id(name.contains("meeting") ? 1 : 2)
        let path = Fixture.path(id, in: root)
        try data.write(to: path)
        let files = SessionFiles(directory: root)

        let loaded = try await files.load(id)
        #expect(loaded.id == id)
        #expect(loaded.version == 1)
        #expect(loaded.createdAt == Fixture.createdAt)
        #expect(loaded.updatedAt == Fixture.updatedAt)
        let entry = try #require(try await files.list().first)
        #expect(entry.id == id)
        #expect(entry.title == (name.contains("meeting") ? "設計 Review" : "字幕 Conference"))
        #expect(entry.kind == (name.contains("meeting") ? "Meeting" : "Conference"))
        #expect(entry.failure == nil)
        #expect(try Fixture.canonical(JSONEncoder().encode(loaded)) == Fixture.canonical(data))
        #expect(try Data(contentsOf: path) == data)

        let saved = try await files.save(loaded.snapshot, now: Fixture.updatedAt)
        #expect(saved == loaded)
        #expect(try Fixture.canonical(Data(contentsOf: path)) == Fixture.canonical(data))
        #expect(try await SessionFiles(directory: root).load(id) == loaded)
        let fresh = SessionFiles(directory: root.appendingPathComponent("fresh"))
        let created = try await fresh.save(loaded.snapshot, now: Fixture.createdAt)
        var expected = try Fixture.object(data)
        expected["updatedAt"] = 100
        #expect(created.createdAt == Fixture.createdAt)
        #expect(try Fixture.canonical(Data(contentsOf: Fixture.path(id, in: root.appendingPathComponent("fresh"))))
                == Fixture.canonical(JSONSerialization.data(withJSONObject: expected)))
    }

    @Test(arguments: ["r3-meeting-basic", "r3-meeting-extended"])
    func meetingRestoresSpeechCandidatesSummaryAndOptionalAssistance(name: String) throws {
        let saved = try JSONDecoder().decode(SavedSession.self, from: Fixture.data(name))
        guard case .meeting(let value, let cards) = saved.snapshot else {
            Issue.record("Expected Meeting fixture"); return
        }
        #expect(value.events.map(\.text) == ["次回に料金を確認します", "We will review the price."])
        #expect(value.events.map(\.origin) == [.microphone, .systemAudio])
        #expect(value.events.map(\.startOffset) == [1.25, 3.5])
        #expect(value.events.map(\.sourceStartTime) == [0.25, nil])
        #expect(value.events.map(\.languageCode) == ["ja-JP", "en-US"])
        #expect(value.startedAt == Date(timeIntervalSinceReferenceDate: 50))
        #expect(value.candidates.map(\.review) == [.confirmed, .unreviewed, .rejected])
        #expect(value.candidates.map(\.insight.kind) == [.actionCandidate, .decisionCandidate, .actionCandidate])
        #expect(value.candidates[0].evidenceIDs == [try Fixture.id(101)])
        #expect(cards.map(\.kind) == [.answerSuggestion, .followUpQuestion, .risk])
        let summary = try #require(value.summary)
        #expect(summary.answerLanguage == .japanese)
        #expect(summary.sections.map(\.text) == ["料金確認を予定"])
        #expect(summary.sections[0].supplement == "料金資料の補足")
        #expect(summary.sections[0].knowledgeReferences[0].snippet == "料金は100円です。")
        #expect(summary.sections[0].knowledgeReferences[0].startLine == 2)
        #expect(summary.sections[0].knowledgeReferences[0].characterOffset == 5)
        #expect(saved.snapshot.markdown.contains("次回に料金を確認します"))
        #expect(saved.snapshot.markdown.contains("料金は100円です。"))
        #expect(saved.snapshot.markdown.contains("料金確認を予定"))

        if name == "r3-meeting-basic" {
            #expect(value.translations == nil)
            #expect(value.assistance == nil)
            #expect(cards.allSatisfy { $0.webReferences == nil && $0.searchSuggestionsHTML == nil })
        } else {
            #expect(value.translations?.map(\.text) == ["We will check the price next time.", "料金を確認します。"])
            #expect(value.translations?.map(\.id) == [try Fixture.id(101), try Fixture.id(102)])
            #expect(value.translations?.map(\.targetLanguage) == ["en", "ja"])
            let answer = try #require(value.assistance?.first)
            #expect(answer.text == "資料とWebの回答 🔎\n確認してください。")
            #expect(answer.knowledgeReferences[0].source?.path == "Sources/Price.swift")
            #expect(answer.webReferences?.first?.url.absoluteString == "https://example.com/price?q=100")
            #expect(answer.webReferences?.first?.fetchedAt == Date(timeIntervalSinceReferenceDate: 75))
            #expect(answer.searchSuggestionsHTML == "<div>price &amp; plan</div>")
            #expect(saved.snapshot.markdown.contains("We will check the price next time."))
            #expect(saved.snapshot.markdown.contains("料金を確認します。"))
            #expect(saved.snapshot.markdown.contains("https://example.com/price?q=100"))
            #expect(saved.snapshot.markdown.contains("Sources/Price.swift"))
        }
    }

    @Test(arguments: ["r3-conference-basic", "r3-conference-extended"])
    func conferenceRestoresTranslationStatesAndOptionalSupport(name: String) throws {
        let saved = try JSONDecoder().decode(SavedSession.self, from: Fixture.data(name))
        guard case .conference(let value) = saved.snapshot else {
            Issue.record("Expected Conference fixture"); return
        }
        #expect(value.units.map(\.translationState) == [.pending, .translating, .done, .failed("モデル準備失敗")])
        #expect(value.units.map(\.japanese) == [nil, nil, "料金は100円です。", nil])
        #expect(value.units[2].segmentIDs == [try Fixture.id(203)])
        #expect(value.segments[2].english == "The price is 100 yen.")
        #expect(value.segments[0].startTime == nil)
        #expect(value.segments[2].finalizedAt == Date(timeIntervalSinceReferenceDate: 53))
        #expect(saved.snapshot.markdown.contains("The price is 100 yen."))
        #expect(saved.snapshot.markdown.contains("料金は100円です。"))
        #expect(saved.snapshot.markdown.contains("(untranslated)"))
        if name == "r3-conference-basic" {
            #expect(value.support == nil)
            #expect(value.segments.allSatisfy { $0.origin == nil && $0.sessionOffset == nil && $0.languageCode == nil })
        } else {
            #expect(value.segments.map(\.origin) == [.microphone, .systemAudio, .microphone, .systemAudio])
            #expect(value.segments.map(\.sessionOffset) == [1.5, 2.5, 3.5, 4.5])
            #expect(value.segments.map(\.languageCode) == ["en-US", "en-US", "en-US", "en-US"])
            let support = try #require(value.support)
            #expect(support.answers[0].text == "資料とWebの回答 🔎\n確認してください。")
            #expect(support.corrections[0].adopted)
            #expect(support.corrections[0].unitID == (try Fixture.id(303)))
            #expect(support.corrections[0].original.sourceText == "The price is 100 yen.")
            #expect(support.corrections[0].original.translation == "料金は100円です。")
            #expect(support.corrections[0].sourceText == "The monthly price is 100 yen.")
            #expect(support.corrections[0].translation == "月額は100円です。")
            #expect(support.terms[0].term == "price")
            #expect(support.terms[0].target == "料金")
            #expect(support.corrections[0].original.terms == support.terms)
            #expect(saved.snapshot.markdown.contains("The monthly price is 100 yen."))
            #expect(saved.snapshot.markdown.contains("月額は100円です。"))
            #expect(saved.snapshot.markdown.contains("Sources/Price.swift"))
            #expect(saved.snapshot.markdown.contains("https://example.com/price?q=100"))
        }
    }
}
