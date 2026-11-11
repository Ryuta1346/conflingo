import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepositoryKnowledgeTests {
    @Test func importsSelectedSourceWithStablePathsVersionsAndIdentifierSearch() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("Sources/PaymentService.swift", "// 支払い処理\nfunc refundPayment() { }\n")
        try fixture.write("Tests/PaymentService.swift", "// 支払い処理\nfunc refundPayment() { }\n")
        try fixture.write("README.md", "支払い機能は PaymentService が担当する。")
        let scan = try await RepositoryImporter.scan(fixture.root)
        let snapshot = try await RepositoryImporter.load(scan, selected: Set(scan.eligible.map(\.path)))
        let index = KnowledgeIndex()
        let documents = try await index.addRepository(snapshot)
        #expect(documents.count == 3)
        let hits = try await index.search("refund payment")
        #expect(Set(hits.prefix(2).compactMap { $0.source?.path }) == ["Sources/PaymentService.swift", "Tests/PaymentService.swift"])
        #expect(hits.allSatisfy { $0.source?.snapshotID == snapshot.id && $0.source?.contentHash.count == 64 })
        let source = try #require(hits.first)
        try fixture.write("Sources/PaymentService.swift", "changed")
        #expect(try await index.references(for: source.documentID).first?.snippet == source.snippet)
        #expect(try await index.search("支払い").isEmpty == false)
    }

    @Test func excludesSecretsGeneratedFilesNestedRepositoriesAndLinks() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        for path in ["app.swift", ".env", "credentials.json", "node_modules/pkg/index.js", "build/generated.swift", "nested/.git/HEAD", "nested/code.swift", "package-lock.json"] {
            try fixture.write(path, "synthetic")
        }
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("linked.swift").path, withDestinationPath: "/etc/passwd")
        let scan = try await RepositoryImporter.scan(fixture.root)
        #expect(scan.eligible.map(\.path) == ["app.swift"])
        #expect(scan.entries.filter { $0.reason != nil }.count >= 6)
    }

    @Test func replacementWithLinkAfterPreviewFailsWithoutPublishingAnyFiles() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("a.swift", "func safe() {}")
        try fixture.write("b.swift", "func original() {}")
        let scan = try await RepositoryImporter.scan(fixture.root)
        try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("b.swift"))
        try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("b.swift").path, withDestinationPath: "/etc/passwd")
        await #expect(throws: (any Error).self) {
            _ = try await RepositoryImporter.load(scan, selected: Set(scan.eligible.map(\.path)))
        }
    }

    @Test func limitsInvalidEncodingAndUnselectedPathsAreRejected() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("a.swift", "abcd")
        try fixture.write("b.swift", "efgh")
        let scan = try await RepositoryImporter.scan(fixture.root)
        await #expect(throws: (any Error).self) {
            _ = try await RepositoryImporter.load(scan, selected: ["../outside.swift"])
        }
        await #expect(throws: (any Error).self) {
            _ = try await RepositoryImporter.load(scan, selected: ["a.swift", "b.swift"], limits: RepositoryLimits(files: 1))
        }
        await #expect(throws: (any Error).self) {
            _ = try await RepositoryImporter.load(scan, selected: ["a.swift", "b.swift"], limits: RepositoryLimits(characters: 7))
        }
        try Data([0xFF, 0x00]).write(to: fixture.root.appendingPathComponent("a.swift"))
        let invalid = try await RepositoryImporter.scan(fixture.root)
        await #expect(throws: (any Error).self) { _ = try await RepositoryImporter.load(invalid, selected: ["a.swift"]) }
    }

    @Test func removalInvalidatesRepositoryAndKeepsOrdinaryDocuments() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("app.swift", "// repository needle")
        let scan = try await RepositoryImporter.scan(fixture.root)
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("ordinary needle".utf8), filename: "notes.md")
        await knowledge.importRepository(scan, selected: ["app.swift"])
        #expect(knowledge.documents.count == 2)
        await knowledge.removeRepository()
        #expect(knowledge.documents.count == 1)
        await knowledge.search("needle")
        #expect(knowledge.results.count == 1)
        #expect(knowledge.results.first?.source == nil)
    }
}

struct RepositoryFixture {
    let root: URL
    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("repository-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    func write(_ path: String, _ body: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url)
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
