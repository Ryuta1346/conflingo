import Foundation
import Testing
@testable import ConfLingo

@Suite(.timeLimit(.minutes(1)))
struct KnowledgeGoldenTests {
    private typealias Fixture = PersistenceGoldenFixture

    @Test(arguments: Fixture.knowledgeNames)
    func historicalV1LoadsAndEncodesWithoutLosingFields(name: String) async throws {
        let data = try Fixture.data(name)
        let root = try Fixture.directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try Fixture.id(3)
        let path = Fixture.path(id, in: root)
        try data.write(to: path)
        let files = KnowledgeLibraryFiles(directory: root)

        let loaded = try await files.load(id)
        #expect(loaded.id == id)
        #expect(loaded.revision == (try Fixture.id(4)))
        #expect(loaded.version == 1)
        #expect(loaded.createdAt == Fixture.createdAt)
        #expect(loaded.updatedAt == Fixture.updatedAt)
        #expect(try await files.list() == [loaded.entry])
        #expect(loaded.entry.failure == nil)
        #expect(loaded.title == "料金資料")
        #expect(try Fixture.canonical(JSONEncoder().encode(loaded)) == Fixture.canonical(data))
        #expect(try Data(contentsOf: path) == data)

        let unchanged = try await files.save(loaded.content, title: loaded.title, replacing: id,
                                             expectedRevision: loaded.revision, now: Date(timeIntervalSinceReferenceDate: 300))
        #expect(unchanged == loaded)
        #expect(try Data(contentsOf: path) == data)
        let replacement = try await files.save(loaded.content, title: "新版料金", replacing: id,
                                               expectedRevision: loaded.revision, now: Date(timeIntervalSinceReferenceDate: 300))
        var expected = try Fixture.object(data)
        expected["title"] = "新版料金"
        expected["updatedAt"] = 300
        expected["revision"] = replacement.revision.uuidString
        #expect(replacement.revision != loaded.revision)
        #expect(replacement.id == loaded.id)
        #expect(replacement.createdAt == loaded.createdAt)
        #expect(try Fixture.canonical(Data(contentsOf: path)) == Fixture.canonical(JSONSerialization.data(withJSONObject: expected)))
        #expect(try await KnowledgeLibraryFiles(directory: root).load(id) == replacement)

        let freshRoot = root.appendingPathComponent("fresh")
        let fresh = try await KnowledgeLibraryFiles(directory: freshRoot).save(loaded.content, title: loaded.title, now: Fixture.createdAt)
        expected = try Fixture.object(data)
        expected["id"] = fresh.id.uuidString
        expected["revision"] = fresh.revision.uuidString
        expected["updatedAt"] = 100
        #expect(fresh.createdAt == Fixture.createdAt)
        #expect(fresh.updatedAt == Fixture.createdAt)
        #expect(try Fixture.canonical(Data(contentsOf: Fixture.path(fresh.id, in: freshRoot)))
                == Fixture.canonical(JSONSerialization.data(withJSONObject: expected)))
    }

    @Test(arguments: Fixture.knowledgeNames)
    func restoredV1DocumentsRemainSearchableWithOriginalProvenance(name: String) async throws {
        let saved = try JSONDecoder().decode(SavedKnowledge.self, from: Fixture.data(name))
        let index = KnowledgeIndex()
        let docs = try await index.restore(saved.content)
        let hits = try await index.search("price")
        let first = try #require(hits.first)
        #expect(!first.snippet.isEmpty)
        #expect(first.importedAt == Date(timeIntervalSinceReferenceDate: 50))
        #expect(docs[0].id == (try Fixture.id(401)))
        if name == "r3-knowledge-document" {
            #expect(docs.count == 1)
            #expect(saved.content.documents[0].body == "# Price\n料金は100円です。\n")
            #expect(saved.content.documents[0].document.characterCount == 19)
            #expect(first.source == nil)
            #expect(first.documentID == docs[0].id)
            #expect(first.snippet.contains("料金は100円です。"))
        } else {
            #expect(docs.count == 2)
            #expect(docs.map { $0.source?.path } == ["Sources/Price.swift", "Docs/price.md"])
            #expect(saved.content.documents.map(\.body) == ["let price = 100\n", "# Price\nMonthly price is 100 yen.\n"])
            for (doc, item) in zip(docs, saved.content.documents) {
                let reference = try #require(try await index.references(for: doc.id).first)
                #expect(reference.source?.snapshotID == (try Fixture.id(500)))
                #expect(reference.source?.name == "Demo")
                #expect(reference.source?.contentHash == KnowledgeArchive.hash(item.body))
                #expect(reference.source?.path == doc.source?.path)
                #expect(reference.importedAt == Date(timeIntervalSinceReferenceDate: 50))
            }
            #expect(first.source?.name == "Demo")
        }
    }
}
