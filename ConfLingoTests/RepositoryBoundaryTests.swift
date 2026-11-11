import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RepositoryBoundaryTests {
    @Test(arguments: ["file", "directory", "root"])
    func replacedPreviewTargetsAreRejected(target: String) async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("Sources/a.swift", "let original = 1")
        let scan = try await RepositoryImporter.scan(fixture.root)
        if target == "file" { try fixture.write("Sources/a.swift", "let changed = 2") }
        if target == "directory" {
            try FileManager.default.removeItem(at: fixture.root.appendingPathComponent("Sources"))
            try FileManager.default.createSymbolicLink(atPath: fixture.root.appendingPathComponent("Sources").path, withDestinationPath: "/etc")
        }
        if target == "root" {
            let moved = fixture.root.appendingPathExtension("moved")
            try FileManager.default.moveItem(at: fixture.root, to: moved)
            defer { try? FileManager.default.removeItem(at: moved) }
            try FileManager.default.createDirectory(at: fixture.root, withIntermediateDirectories: true)
            await #expect(throws: (any Error).self) { _ = try await RepositoryImporter.load(scan, selected: ["Sources/a.swift"]) }
            return
        }
        await #expect(throws: (any Error).self) { _ = try await RepositoryImporter.load(scan, selected: ["Sources/a.swift"]) }
    }

    @Test func scanningAndLoadingHonorBoundariesAndCancellation() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("Sources/a.swift", "1234")
        let scan = try await RepositoryImporter.scan(fixture.root)
        let atLimit = try await RepositoryImporter.load(scan, selected: ["Sources/a.swift"], limits: RepositoryLimits(files: 1, characters: 4, bytes: 4))
        #expect(atLimit.files.count == 1)
        await #expect(throws: (any Error).self) {
            _ = try await RepositoryImporter.load(scan, selected: ["Sources/a.swift"], limits: RepositoryLimits(bytes: 3))
        }
        await #expect(throws: (any Error).self) { _ = try await RepositoryImporter.scan(fixture.root, limits: RepositoryLimits(entries: 1)) }
        await #expect(throws: (any Error).self) { _ = try await RepositoryImporter.scan(fixture.root, limits: RepositoryLimits(depth: 0)) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RepositoryImporter.load(scan, selected: ["Sources/a.swift"])
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    @Test func normalizedUnicodeAndLongLinesPreserveCitationPositions() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        let body = "// 認証\r\n" + String(repeating: "あ", count: 1_250) + "\r\nfunc verifyToken() {}\r\n"
        try fixture.write("Sources/Auth.swift", body)
        let scan = try await RepositoryImporter.scan(fixture.root)
        let index = KnowledgeIndex()
        let documents = try await index.addRepository(RepositoryImporter.load(scan, selected: ["Sources/Auth.swift"]))
        let document = try #require(documents.first)
        let references = try await index.references(for: document.id)
        #expect(references.map(\.snippet).joined() == body.replacingOccurrences(of: "\r\n", with: "\n"))
        let result = try #require(try await index.search("verifyToken").first)
        #expect(result.startLine <= 3 && result.endLine == 3)
        #expect(result.source?.path == "Sources/Auth.swift")
    }

    @Test func failedBatchKeepsOrdinaryDocumentsAndDoesNotPublishPartialRepository() async throws {
        let fixture = try RepositoryFixture()
        defer { fixture.remove() }
        try fixture.write("a.swift", "let first = true")
        try fixture.write("z.swift", "let last = true")
        let scan = try await RepositoryImporter.scan(fixture.root)
        try fixture.write("z.swift", "changed")
        let knowledge = KnowledgeStore()
        await knowledge.add(data: Data("ordinary".utf8), filename: "notes.md")
        await knowledge.importRepository(scan, selected: ["a.swift", "z.swift"])
        #expect(!knowledge.isBusy)
        #expect(!knowledge.hasRepository)
        #expect(knowledge.documents.map(\.title) == ["notes.md"])
        await knowledge.search("first")
        #expect(knowledge.results.isEmpty)
    }

    @Test func repositoryCitationCannotInjectMarkdownAndContainsFullRelativePath() async throws {
        let store = summaryStore(count: 1)
        var ref = reference("x.md", snippet: "<script>\n# not a heading")
        ref.source = RepositorySource(snapshotID: UUID(), name: "repo\n# fake", path: "src/first\n# forged.swift", contentHash: String(repeating: "b", count: 64))
        let plan = try MeetingSummaryPlan(sessionID: store.sessionID, events: store.finals, answerLanguage: .japanese,
                                          knowledgeBySection: [[ref]], knowledgeRevision: UUID())
        let coordinator = MeetingSummaryCoordinator(store: store, client: RepositorySummaryClient())
        await coordinator.generate(plan, consent: true)
        let output = MeetingExportSnapshot(title: "test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en", sessionID: store.sessionID,
                                            events: store.finals, candidates: [], summary: coordinator.completed).markdown
        #expect(!output.contains("\n# forged"))
        #expect(!output.contains("<script>"))
        #expect(output.contains("src/first"))
        #expect(output.contains("bbbbbbbbbbbb"))
    }
}
