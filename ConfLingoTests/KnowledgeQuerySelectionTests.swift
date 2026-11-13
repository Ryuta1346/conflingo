import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct KnowledgeQuerySelectionTests {
    private let fillers = "amber anchor apple apron arrow artist atlas atom autumn badge baker bamboo banner barrel basket beach beacon bean bear beauty bedroom bell bench berry bicycle bird blanket blossom boat book bottle branch bread breeze bridge bronze brush bucket butter cabin"
        .split(separator: " ").map(String.init)

    @Test(arguments: ["zebra", "ZEBRA", "ｚｅｂｒａ", "月額"])
    func leadingTargetSurvivesMoreThan32DistinctWords(target: String) async throws {
        let index = KnowledgeIndex()
        let body = target == "月額" ? "料金は月額100円です。" : "zebra"
        let document = try await index.add(data: Data(body.utf8), filename: "target.md")
        _ = try await index.add(data: Data("月の満ち欠け。額の傷。".utf8), filename: "unrelated.md")

        let hits = try await index.search(([target] + fillers).joined(separator: " "))

        #expect(hits.map(\.documentID) == [document.id])
        #expect(hits.first?.snippet == body)
    }

    @Test(arguments: [30, 31, 32])
    func onlyFirst32DistinctWordsAreSearched(precedingCount: Int) async throws {
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data("zebra".utf8), filename: "target.md")
        let query = (Array(fillers.prefix(precedingCount)) + ["zebra"]).joined(separator: " ")

        let hits = try await index.search(query)

        #expect(hits.map(\.documentID) == (precedingCount < 32 ? [document.id] : []))
    }

    @Test func alphabeticallyEarlier33rdWordCannotDisplaceLeadingTarget() async throws {
        let index = KnowledgeIndex()
        let first = try await index.add(data: Data("zebra".utf8), filename: "first.md")
        _ = try await index.add(data: Data("aardvark".utf8), filename: "last.md")
        let query = (["zebra"] + fillers.prefix(31) + ["aardvark"]).joined(separator: " ")

        #expect(try await index.search(query).map(\.documentID) == [first.id])
    }

    @Test func duplicatesAndStopWordsDoNotConsumeTheWordBudget() async throws {
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data("zebra".utf8), filename: "target.md")
        let repeated = Array(repeating: "amber AMBER ａｍｂｅｒ the THE は の", count: 5)
        let query = (repeated + fillers.prefix(31) + ["ZEBRA", "zebra"]).joined(separator: " ")

        #expect(try await index.search(query).map(\.documentID) == [document.id])
    }

    @Test(arguments: ["zebraTarget", "zebra_target"])
    func leadingIdentifierKeepsRepositoryCitation(identifier: String) async throws {
        let index = KnowledgeIndex()
        let body = "// implementation\n"
        let snapshot = RepositorySnapshot(id: UUID(), name: "Fixture", importedAt: Date(), files: [
            .init(path: "src/\(identifier).swift", body: body, hash: KnowledgeArchive.hash(body))
        ])
        _ = try await index.addRepository(snapshot)
        let original = try #require(try await index.search(identifier).first)

        let hits = try await index.search(([identifier] + fillers).joined(separator: " "))

        #expect(hits == [original])
        #expect(hits.first?.source?.path == "src/\(identifier).swift")
        #expect(hits.first?.source?.snapshotID == snapshot.id)
        #expect(hits.first?.source?.contentHash == KnowledgeArchive.hash(body))
        #expect(hits.first?.snippet == body)
        #expect(hits.first?.startLine == 1)
        #expect(hits.first?.characterOffset == 0)
    }

    @Test func restoredDocumentSupportsLongQueryAndPreservesCitationLocation() async throws {
        let index = KnowledgeIndex()
        let body = String(repeating: "x ", count: 599) + "\n料金は月額100円です。"
        let document = try await index.add(data: Data(body.utf8), filename: "billing.md")
        let original = try #require(try await index.search("月額").first)
        let archive = try await index.archive(documentID: document.id)
        let restored = KnowledgeIndex()
        _ = try await restored.restore(archive)

        let hits = try await restored.search((["月額"] + fillers).joined(separator: " "))

        #expect(hits.count == 1)
        #expect(hits.first?.documentID == original.documentID)
        #expect(hits.first?.snippet == original.snippet)
        #expect(hits.first?.startLine == 2)
        #expect(hits.first?.characterOffset == 1_199)
    }

    @Test func queryCharacterLimitAndQuotedSyntaxRemainBounded() async throws {
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data("zebra".utf8), filename: "target.md")
        #expect(try await index.search(String(repeating: " ", count: 2_000) + "zebra").isEmpty)
        #expect(try await index.search("zebra" + String(repeating: " ", count: 1_995)).map(\.documentID) == [document.id])
        let query = (["\"zebra\" OR * : ( )"] + fillers).joined(separator: " ")
        #expect(try await index.search(query).map(\.documentID) == [document.id])
        #expect(try await index.search("\" * : ( ) OR the は").isEmpty)
    }

    @Test func shortQueryRetainsPathRankingAndStableTieOrder() async throws {
        let index = KnowledgeIndex()
        let snapshot = RepositorySnapshot(id: UUID(), name: "Fixture", importedAt: Date(), files: [
            .init(path: "zebra.md", body: "guide", hash: KnowledgeArchive.hash("guide")),
            .init(path: "one.md", body: "zebra guide", hash: KnowledgeArchive.hash("zebra guide")),
            .init(path: "two.md", body: "zebra guide", hash: KnowledgeArchive.hash("zebra guide"))
        ])
        _ = try await index.addRepository(snapshot)

        let hits = try await index.search("zebra guide")

        #expect(hits.compactMap { $0.source?.path } == ["zebra.md", "one.md", "two.md"])
        #expect(try await index.search("guide zebra") == hits)
    }
}
