import Darwin
import Foundation
import Testing
@testable import ConfLingo

struct KnowledgeLibraryPersistenceTests {
    @Test func savedTextSurvivesNewStoreAndSourceDeletion() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let index = KnowledgeIndex()
        let doc = try await index.add(data: Data("料金\r\n100円".utf8), filename: "price.md")
        let archive = try await index.archive(documentID: doc.id)
        let saved = try await KnowledgeLibraryFiles(directory: root).save(archive, title: "料金資料")
        let reopened = try await KnowledgeLibraryFiles(directory: root).load(saved.id)
        #expect(reopened == saved)
        let next = KnowledgeIndex()
        _ = try await next.restore(reopened.content)
        let hits = try await next.search("料金")
        #expect(hits.first?.snippet == "料金\n100円")
        #expect(hits.first?.importedAt == doc.importedAt)
    }

    @Test func identicalResavePreservesRevisionAndTimestamp() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let archive = try await libraryArchive()
        let saved = try await files.save(archive, title: "Price", now: Date(timeIntervalSince1970: 100))
        let again = try await files.save(archive, title: "Price", replacing: saved.id,
                                        expectedRevision: saved.revision, now: Date(timeIntervalSince1970: 200))
        #expect(again == saved)
    }

    @Test func replacementAndDeletionDoNotChangeAnAttachedSnapshot() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let original = try await libraryArchive("料金100円")
        let saved = try await files.save(original, title: "料金")
        let attached = KnowledgeIndex()
        _ = try await attached.restore(saved.content)
        let changed = try await files.save(try await libraryArchive("料金200円"), title: "新版", replacing: saved.id, expectedRevision: saved.revision)
        #expect(changed.id == saved.id)
        #expect(changed.createdAt == saved.createdAt)
        #expect(changed.revision != saved.revision)
        await #expect(throws: (any Error).self) {
            try await files.save(original, title: "stale", replacing: saved.id, expectedRevision: saved.revision)
        }
        try await files.delete(saved.id)
        #expect(try await files.list().isEmpty)
        #expect(try await attached.search("料金").first?.snippet == "料金100円")
    }

    @Test func failedWriteAndDeleteRetainPreviousFile() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = try await KnowledgeLibraryFiles(directory: root).save(try await libraryArchive(), title: "Original")
        let files = KnowledgeLibraryFiles(directory: root, write: { _, _ in throw CocoaError(.fileWriteNoPermission) },
                                         remove: { _ in throw CocoaError(.fileWriteNoPermission) })
        await #expect(throws: (any Error).self) {
            try await files.save(try await libraryArchive("changed"), title: "Changed", replacing: original.id, expectedRevision: original.revision)
        }
        await #expect(throws: (any Error).self) { try await files.delete(original.id) }
        #expect(try await files.load(original.id) == original)
    }

    @Test func corruptUnknownAndLinkedFilesDoNotHideHealthyEntries() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let saved = try await files.save(try await libraryArchive(), title: "Good")
        let broken = root.appendingPathComponent(UUID().uuidString + ".json")
        let future = root.appendingPathComponent(UUID().uuidString + ".json")
        try Data("broken".utf8).write(to: broken)
        try Data("{\"version\":99}".utf8).write(to: future)
        let alias = UUID()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(alias.uuidString + ".json"),
            withDestinationURL: root.appendingPathComponent(saved.id.uuidString + ".json"))
        let entries = try await files.list()
        #expect(entries.count == 4)
        #expect(entries.filter { $0.failure != nil }.count == 3)
        try await files.delete(alias)
        #expect(try await files.load(saved.id) == saved)
        #expect(try Data(contentsOf: broken) == Data("broken".utf8))
    }

    @Test func capacityFailureDoesNotReplaceAnExistingRecord() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root, limits: .init(items: 1, bytes: 5_000, itemBytes: 4_000))
        let saved = try await files.save(try await libraryArchive(), title: "First")
        await #expect(throws: (any Error).self) { try await files.save(try await libraryArchive("other"), title: "Second") }
        await #expect(throws: (any Error).self) {
            try await files.save(try await libraryArchive(String(repeating: "a", count: 6_000)), title: "Too big",
                                 replacing: saved.id, expectedRevision: saved.revision)
        }
        #expect(try await files.load(saved.id) == saved)
    }

    @Test func repositoryRoundTripRetainsSelectedPathsAndHashes() async throws {
        let index = KnowledgeIndex()
        let body = "let price = 100"
        let snapshot = RepositorySnapshot(id: UUID(), name: "Project", importedAt: Date(timeIntervalSince1970: 100),
            files: [.init(path: "Sources/Price.swift", body: body, hash: KnowledgeArchive.hash(body))])
        _ = try await index.addRepository(snapshot)
        let archive = try await index.archive(documentID: nil)
        let other = KnowledgeIndex()
        let docs = try await other.restore(archive)
        let ref = try #require(try await other.references(for: docs[0].id).first)
        #expect(ref.source?.path == "Sources/Price.swift")
        #expect(ref.source?.snapshotID == snapshot.id)
        #expect(ref.source?.contentHash == KnowledgeArchive.hash(body))
        #expect(ref.importedAt == snapshot.importedAt)
        await #expect(throws: (any Error).self) { try await other.restore(archive) }
    }

    @Test func invalidRepositoryCannotBePartiallyAttached() async throws {
        let index = KnowledgeIndex()
        _ = try await index.add(data: Data("既存資料".utf8), filename: "existing.md")
        let base = try await libraryArchive("unsafe")
        let doc = base.documents[0].document
        let source = RepositorySource(snapshotID: UUID(), name: "Repo", path: "../secret", contentHash: "invalid")
        let invalid = KnowledgeArchive(documents: [.init(document: KnowledgeDocument(id: doc.id, title: doc.title,
            importedAt: doc.importedAt, characterCount: 6, source: source), body: "unsafe")])
        await #expect(throws: (any Error).self) { try await index.restore(invalid) }
        #expect(try await index.search("既存").count == 1)
        #expect(try await index.search("unsafe").isEmpty)
    }
}

func temporaryLibrary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("KnowledgeLibrary-" + UUID().uuidString) }
func libraryArchive(_ body: String = "料金100円") async throws -> KnowledgeArchive {
    let index = KnowledgeIndex()
    let doc = try await index.add(data: Data(body.utf8), filename: "spec.md")
    return try await index.archive(documentID: doc.id)
}

extension KnowledgeLibraryPersistenceTests {
    @Test func sourceDeletionDoesNotPreventReuseAndLibraryDeleteLeavesExternalFiles() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.md")
        try "# 料金\n100円".write(to: source, atomically: true, encoding: .utf8)
        let index = KnowledgeIndex()
        let doc = try await index.add(url: source)
        let files = KnowledgeLibraryFiles(directory: root.appendingPathComponent("saved"))
        let saved = try await files.save(try await index.archive(documentID: doc.id), title: "Source")
        try FileManager.default.removeItem(at: source)
        let next = KnowledgeIndex()
        _ = try await next.restore(try await files.load(saved.id).content)
        #expect(try await next.search("料金").first?.snippet == "# 料金\n100円")
        try "Recreated original".write(to: source, atomically: true, encoding: .utf8)
        try await files.delete(saved.id)
        #expect(try String(contentsOf: source, encoding: .utf8) == "Recreated original")
    }

    @Test(arguments: ["../secret", "/absolute", "a//b", "a/./b", "a/../b", "a\0b"])
    func unsafeRepositoryPathsAreRejected(path: String) throws {
        let body = "value"
        let source = RepositorySource(snapshotID: UUID(), name: "Repo", path: path, contentHash: KnowledgeArchive.hash(body))
        let content = KnowledgeArchive(documents: [.init(document: .init(id: UUID(), title: "file", importedAt: Date(),
            characterCount: body.count, source: source), body: body)])
        #expect(throws: (any Error).self) { try content.validate() }
    }

    @Test func attachmentHonorsDocumentLimitsAndDoesNotPublishFailedSearchIndex() async throws {
        let index = KnowledgeIndex()
        for number in 0..<20 { _ = try await index.add(data: Data("文書 \(number)".utf8), filename: "\(number).md") }
        let archive = try await libraryArchive("UniqueLimitSentinel")
        await #expect(throws: (any Error).self) { try await index.restore(archive) }
        #expect(try await index.search("UniqueLimitSentinel").isEmpty)
        #expect(try await index.search("文書").count == 10)
    }

    @Test func corruptBytesCountTowardQuotaAndOversizedFilesAreNotDecoded() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let badID = UUID()
        try Data(repeating: 120, count: 2_001).write(to: root.appendingPathComponent(badID.uuidString + ".json"))
        let files = KnowledgeLibraryFiles(directory: root, limits: .init(items: 100, bytes: 2_000, itemBytes: 2_000))
        await #expect(throws: (any Error).self) { try await files.load(badID) }
        await #expect(throws: (any Error).self) { try await files.save(try await libraryArchive(), title: "Quota") }
        #expect(try await files.list().count == 1)
    }

    @Test func hundredEntriesAndThousandFileRepositoryStayUsable() async throws {
        let root = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = KnowledgeLibraryFiles(directory: root)
        let body = String(repeating: "Synthetic price source for library search.\n", count: 50)
        let snapshot = RepositorySnapshot(id: UUID(), name: "Synthetic", importedAt: Date(), files: (0..<1_000).map {
            .init(path: "Sources/File\($0).swift", body: body, hash: KnowledgeArchive.hash(body))
        })
        let index = KnowledgeIndex()
        _ = try await index.addRepository(snapshot)
        let saved = try await files.save(try await index.archive(documentID: nil), title: "Repository")
        for number in 1..<100 { try await files.save(try await libraryArchive("Price \(number)"), title: "資料 \(number)") }
        let start = ContinuousClock.now
        let entries = try await files.list()
        let listTime = start.duration(to: .now)
        #expect(entries.count == 100)
        #expect(entries.filter { $0.title.localizedCaseInsensitiveContains("資料 99") }.count == 1)
        let next = KnowledgeIndex()
        let restoreStart = ContinuousClock.now
        let documents = try await next.restore(try await files.load(saved.id).content)
        #expect(documents.count == 1_000)
        #expect(try await next.search("price").count == 10)
        print("LIBRARY_BENCHMARK list100=\(listTime) restore1000=\(restoreStart.duration(to: .now))")
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("LIBRARY_MEMORY processPeakBytes=\(usage.ru_maxrss)")
    }
}
