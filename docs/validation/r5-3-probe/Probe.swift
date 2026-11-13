import Foundation

@main
struct Probe {
    static func main() async throws {
        let fillers = "amber anchor apple apron arrow artist atlas atom autumn badge baker bamboo banner barrel basket beach beacon bean bear beauty bedroom bell bench berry bicycle bird blanket blossom boat book bottle branch bread breeze bridge bronze brush bucket butter cabin".split(separator: " ").map(String.init)
        let index = KnowledgeIndex()
        let english = try await index.add(data: Data("zebra".utf8), filename: "english.md")
        let japanese = try await index.add(data: Data("料金は月額100円です。".utf8), filename: "japanese.md")
        let cases: [(String, String, UUID, Bool)] = [
            ("english-short", "zebra", english.id, true),
            ("english-32-unique", (["zebra"] + fillers.prefix(31)).joined(separator: " "), english.id, true),
            ("english-33-unique", (["zebra"] + fillers.prefix(32)).joined(separator: " "), english.id, false),
            ("english-leading-target", (["zebra"] + fillers).joined(separator: " "), english.id, false),
            ("english-trailing-target", (fillers + ["zebra"]).joined(separator: " "), english.id, false),
            ("japanese-short", "月額", japanese.id, true),
            ("japanese-leading-target", (["月額"] + fillers).joined(separator: " "), japanese.id, false),
            ("repeated-target", (Array(repeating: "zebra", count: 5) + fillers).joined(separator: " "), english.id, false)
        ]
        for (name, query, id, expectedCurrentHit) in cases {
            let hit = try await index.search(query).contains { $0.documentID == id }
            precondition(hit == expectedCurrentHit, name)
            print("\(name): chars=\(query.count), found=\(hit)")
        }
        let restored = KnowledgeIndex()
        _ = try await restored.restore(index.archive(documentID: japanese.id))
        let longJapanese = (["月額"] + fillers).joined(separator: " ")
        let restoredHit = try await restored.search(longJapanese).contains { $0.documentID == japanese.id }
        precondition(!restoredHit)
        print("restored-japanese-leading-target: found=\(restoredHit)")
        let repository = KnowledgeIndex()
        _ = try await repository.addRepository(.init(id: UUID(), name: "Fixture", importedAt: Date(), files: [
            .init(path: "src/zebraTarget.swift", body: "implementation", hash: KnowledgeArchive.hash("implementation"))
        ]))
        let shortHit = try await repository.search("zebraTarget").count
        let longHit = try await repository.search((["zebraTarget"] + fillers).joined(separator: " ")).count
        precondition(shortHit == 1 && longHit == 0)
        print("repository-identifier: short=\(shortHit), long=\(longHit)")
    }
}
