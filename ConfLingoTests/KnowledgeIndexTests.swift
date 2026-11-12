import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct KnowledgeIndexTests {
    @Test(arguments: ["月額", " 月額 ", "月額はいくらですか？", "月額 API", "月額 月額"],
          ["# 仕様\n料金は月額100円です。\nAPI rate limit is 50.", "# 月額\n100円です。", "月額 API\n100円です。"])
    func shortJapaneseQueryFindsWholeWordWithoutMatchingUnrelatedCharacters(query: String, body: String) async throws {
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data(body.utf8), filename: "仕様.md")
        _ = try await index.add(data: Data("月の満ち欠けを観察します。額の傷を確認します。".utf8), filename: "無関係.md")

        let hits = try await index.search(query)

        #expect(hits.map(\.documentID) == [document.id])
        #expect(hits.first?.snippet == body)
        #expect(hits.first?.startLine == 1)
        #expect(hits.first?.characterOffset == 0)
    }

    @Test func shortJapaneseQuerySearchesRepositoryBodyAndRetainsCitation() async throws {
        let index = KnowledgeIndex()
        let body = "# Billing\n料金は月額100円です。"
        let snapshot = RepositorySnapshot(id: UUID(), name: "Product", importedAt: Date(), files: [
            .init(path: "docs/BillingGuide.md", body: body, hash: KnowledgeArchive.hash(body))
        ])
        _ = try await index.addRepository(snapshot)

        let hit = try #require(try await index.search("月額").first)

        #expect(hit.snippet == body)
        #expect(hit.source?.path == "docs/BillingGuide.md")
        #expect(hit.source?.snapshotID == snapshot.id)
        #expect(hit.source?.contentHash == KnowledgeArchive.hash(body))
    }

    @Test func citationLocationDistinguishesDocumentOffsetFromLineColumn() async throws {
        let index = KnowledgeIndex()
        let body = String(repeating: String(repeating: "あ", count: 599) + "\n", count: 2) + "料金は100円です"
        let document = try await index.add(data: Data(body.utf8), filename: "lines.md")
        let chunks = try await index.references(for: document.id)
        let citation = try #require(chunks.last)
        #expect(citation.startLine == 3)
        #expect(citation.snippet == "料金は100円です")
        #expect(citation.location == "3行目から（文書先頭から1201文字目）")

        let long = try await index.add(data: Data(String(repeating: "長", count: 1_201).utf8), filename: "long.md")
        let longChunks = try await index.references(for: long.id)
        #expect(longChunks.last?.location == "1行目から（文書先頭から1201文字目）")
    }

    @Test func searchesJapaneseEnglishAndQuotedSyntaxLocally() async throws {
        let index = KnowledgeIndex()
        let document = try await index.add(data: Data("# 仕様\n料金は月額100円です。\n多要素認証を設定します。\nAPI rate limit is 50.".utf8), filename: "仕様.md")
        for query in ["料金はいくらですか？", "認証方式", "API limit", "\"料金\" OR *"] {
            let hits = try await index.search(query)
            #expect(!hits.isEmpty)
            #expect(hits.allSatisfy { $0.documentID == document.id })
            #expect(hits.allSatisfy { $0.title == "仕様.md" && !$0.snippet.isEmpty })
        }
        #expect(try await index.search("銀河宇宙船").isEmpty)
        #expect(try await index.search("\" * : ?").isEmpty)
        #expect(try await index.search("").isEmpty)
    }

    @Test func chunksPreserveExactSourcePositionsAndLongLines() async throws {
        let index = KnowledgeIndex()
        let body = "見出し\n" + String(repeating: "長", count: 2_410) + "\n料金は100円です。"
        let document = try await index.add(data: Data(body.utf8), filename: "long.txt")
        let chunks = try await index.references(for: document.id)
        #expect(chunks.count >= 3)
        #expect(chunks.allSatisfy { $0.snippet.count <= 1_200 })
        #expect(chunks.map(\.snippet).joined() == body)
        for chunk in chunks {
            let start = body.index(body.startIndex, offsetBy: chunk.characterOffset)
            let end = body.index(start, offsetBy: chunk.snippet.count)
            #expect(String(body[start..<end]) == chunk.snippet)
            #expect(chunk.startLine == body[..<start].filter { $0 == "\n" }.count + 1)
        }
    }

    @Test func rejectsInvalidImportsWithoutLosingPreviousData() async throws {
        let index = KnowledgeIndex()
        _ = try await index.add(data: Data("料金100円".utf8), filename: "good.md")
        for (data, name, error) in [
            (Data(), "empty.txt", KnowledgeFailure.empty),
            (Data([0xff, 0xfe]), "invalid.txt", .encoding),
            (Data("pdf".utf8), "a.pdf", .unsupported),
            (Data(repeating: 65, count: 1_048_577), "large.txt", .limit),
            (Data(String(repeating: "a", count: 100_001).utf8), "long.txt", .limit),
            (Data("料金100円".utf8), "duplicate.txt", .duplicate)
        ] {
            await #expect(throws: error) { try await index.add(data: data, filename: name) }
        }
        #expect(try await index.search("料金").count == 1)
    }

    @Test func acceptsBOMAndSameNameDifferentContentThenRemoves() async throws {
        let index = KnowledgeIndex()
        let first = try await index.add(data: Data("\u{feff}料金は100円".utf8), filename: "spec.md")
        let second = try await index.add(data: Data("価格は200円".utf8), filename: "spec.md")
        #expect(first.id != second.id)
        #expect(try await index.references(for: first.id).first?.snippet == "料金は100円")
        try await index.remove(first.id)
        #expect(try await index.search("料金").isEmpty)
        #expect(try await index.search("価格").first?.documentID == second.id)
    }

    @Test func fileImportKeepsSnapshotAfterOriginalChangesAndRejectsMissingFile() async throws {
        let index = KnowledgeIndex()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("source.txt")
        try "料金は100円です".write(to: url, atomically: true, encoding: .utf8)
        let document = try await index.add(url: url)
        try "料金は200円です".write(to: url, atomically: true, encoding: .utf8)
        #expect(try await index.references(for: document.id).first?.snippet == "料金は100円です")
        try FileManager.default.removeItem(at: url)
        #expect(try await index.search("料金").first?.snippet == "料金は100円です")
        await #expect(throws: KnowledgeFailure.unreadable) { try await index.add(url: url) }
    }

    @Test func documentAndTotalCharacterLimitsAreAtomic() async throws {
        let index = KnowledgeIndex()
        for number in 0..<20 { _ = try await index.add(data: Data("料金\(number)".utf8), filename: "\(number).txt") }
        await #expect(throws: KnowledgeFailure.limit) { try await index.add(data: Data("overflow".utf8), filename: "21.txt") }
        #expect(try await index.search("料金").count <= 10)
        let large = KnowledgeIndex()
        for number in 0..<5 {
            _ = try await large.add(data: Data((String(number) + String(repeating: "x ", count: 49_999)).utf8), filename: "\(number).txt")
        }
        await #expect(throws: KnowledgeFailure.limit) { try await large.add(data: Data("another document".utf8), filename: "6.txt") }
    }
}
