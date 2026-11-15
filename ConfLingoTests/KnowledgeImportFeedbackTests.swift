import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct KnowledgeImportFeedbackTests {
    @Test(arguments: [false, true])
    func nextMaterialOperationReplacesBatchResults(repository: Bool) async throws {
        let source = try RepositoryFixture()
        defer { source.remove() }
        try source.write("app.swift", "// repository content")
        try source.write("notes.txt", "A new ordinary document")
        try source.write("empty.txt", "")
        let knowledge = KnowledgeStore()
        if repository {
            let scan = try await RepositoryImporter.scan(source.root)
            await knowledge.importRepository(scan, selected: ["app.swift"])
        }
        let files = KnowledgeLibraryFiles(directory: source.root.appendingPathComponent("library"))
        let saved = try await files.save(try await libraryArchive(), title: "Saved material")
        let library = KnowledgeLibrary(files: files)
        knowledge.setPermission(true)
        await knowledge.importFiles(["notes.txt", "empty.txt"].map { source.root.appendingPathComponent($0) }, canEdit: { true })
        #expect(knowledge.fileImportResults.map(\.kind) == [.success, .failure])
        #expect(!knowledge.permitted)
        let host = DR3Host(KnowledgeMaterialsView(knowledge: knowledge, library: library, fontSize: 16, canEdit: { true }), height: 1000)
        defer { host.close() }
        await host.layout()
        #expect(host.strings.contains { $0.hasPrefix("notes.txt：") })
        #expect(host.strings.contains { $0.hasPrefix("empty.txt：") })

        if repository { await knowledge.removeRepository() }
        else { #expect(await library.attach(saved.id, to: knowledge)) }
        await host.layout()
        let expected = repository ? "リポジトリを取り外しました" : "保存資料を追加しました"
        #expect(host.strings.contains { $0.contains(expected) })
        #expect(!host.strings.contains { $0.hasPrefix("notes.txt：") || $0.hasPrefix("empty.txt：") })
        #expect(knowledge.fileImportResults.isEmpty)
    }

    @Test func batchKeepsCustomImportAndStopsWhenEditingIsNoLongerAllowed() async throws {
        let source = try RepositoryFixture()
        defer { source.remove() }
        try source.write("first.txt", "First document")
        try source.write("second.txt", "Second document")
        let knowledge = KnowledgeStore()
        var editable = true
        var imported: [String] = []
        await knowledge.importFiles(["first.txt", "second.txt"].map { source.root.appendingPathComponent($0) }, canEdit: { editable }) { url in
            imported.append(url.lastPathComponent)
            await knowledge.add(url: url)
            editable = false
        }
        #expect(imported == ["first.txt"])
        #expect(knowledge.documents.map(\.title) == ["first.txt"])
        #expect(knowledge.fileImportResults.count == 1)
    }

    @Test func resetRejectsLateBatchFeedback() async throws {
        let source = try RepositoryFixture()
        defer { source.remove() }
        try source.write("first.txt", "First document")
        let knowledge = KnowledgeStore()
        let gate = TestGate()
        let pending = Task {
            await knowledge.importFiles([source.root.appendingPathComponent("first.txt")], canEdit: { true }) { url in
                await knowledge.add(url: url)
                await gate.wait()
            }
        }
        await gate.entered.next()
        knowledge.reset()
        gate.release()
        await pending.value
        #expect(knowledge.documents.isEmpty)
        #expect(knowledge.fileImportResults.isEmpty)
        #expect(knowledge.notice == nil)
    }
}
