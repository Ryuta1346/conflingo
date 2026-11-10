import Foundation
import NaturalLanguage
import SQLite3

actor KnowledgeIndex {
    private var database: KnowledgeDatabase?
    private var documents: [KnowledgeDocument] = []
    private var bodies: [UUID: String] = [:]
    private var chunks: [UUID: KnowledgeReference] = [:]

    func add(url: URL) throws -> KnowledgeDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.isFileURL, try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw KnowledgeFailure.unreadable
            }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: 1_048_577) ?? Data()
            return try add(data: data, filename: url.lastPathComponent)
        } catch let failure as KnowledgeFailure { throw failure } catch { throw KnowledgeFailure.unreadable }
    }

    func add(data: Data, filename: String) throws -> KnowledgeDocument {
        try Task.checkCancellation()
        guard ["md", "txt"].contains((filename as NSString).pathExtension.lowercased()) else { throw KnowledgeFailure.unsupported }
        guard data.count <= 1_048_576 else { throw KnowledgeFailure.limit }
        guard var body = String(data: data, encoding: .utf8), !body.contains("\0") else { throw KnowledgeFailure.encoding }
        if body.first == "\u{feff}" { body.removeFirst() }
        body = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KnowledgeFailure.empty }
        guard body.count <= 100_000, documents.count < 20,
              documents.reduce(0, { $0 + $1.characterCount }) + body.count <= 500_000 else { throw KnowledgeFailure.limit }
        guard !bodies.values.contains(body) else { throw KnowledgeFailure.duplicate }
        let document = KnowledgeDocument(id: UUID(), title: String((filename as NSString).lastPathComponent.prefix(200)),
                                         importedAt: Date(), characterCount: body.count)
        let references = Self.split(body, document: document)
        let database = try connection()
        try database.execute("BEGIN")
        do {
            for reference in references {
                try Task.checkCancellation()
                try database.execute("INSERT INTO chunks(id, document, words) VALUES (?, ?, ?)",
                                     [reference.id.uuidString, document.id.uuidString, Self.words(reference.snippet).joined(separator: " ")])
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
        documents.append(document)
        bodies[document.id] = body
        for reference in references { chunks[reference.id] = reference }
        return document
    }

    func references(for id: UUID) throws -> [KnowledgeReference] {
        chunks.values.filter { $0.documentID == id }.sorted { $0.characterOffset < $1.characterOffset }
    }

    func remove(_ id: UUID) throws {
        try connection().execute("DELETE FROM chunks WHERE document = ?", [id.uuidString])
        documents.removeAll { $0.id == id }
        bodies[id] = nil
        chunks = chunks.filter { $0.value.documentID != id }
    }

    func search(_ query: String) throws -> [KnowledgeReference] {
        try Task.checkCancellation()
        let terms = Self.words(String(query.prefix(2_000))).filter { !Self.stopWords.contains($0) }
        guard !terms.isEmpty else { return [] }
        let expression = Array(Set(terms)).sorted().prefix(32).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: " OR ")
        let ids = try connection().query("SELECT id FROM chunks WHERE chunks MATCH ? ORDER BY rank, rowid LIMIT 10", [expression])
        try Task.checkCancellation()
        return ids.compactMap { UUID(uuidString: $0).flatMap { chunks[$0] } }
    }

    private func connection() throws -> KnowledgeDatabase {
        if let database { return database }
        let new = try KnowledgeDatabase()
        database = new
        return new
    }

    private static func words(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            if word.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { words.append(word) }
            return true
        }
        return words
    }

    private static let stopWords: Set<String> = [
        "は", "が", "の", "を", "に", "で", "と", "も", "へ", "や", "か", "な", "ね", "です", "ます", "だ", "する", "し", "て", "い", "ある", "いる",
        "どう", "なっ", "いくら", "どの", "この", "その", "それ", "これ", "について", "ください", "教え", "教えて",
        "a", "an", "the", "is", "are", "was", "were", "to", "of", "in", "on", "and", "or", "what", "how", "does", "do", "it", "please"
    ]

    private static func split(_ text: String, document: KnowledgeDocument) -> [KnowledgeReference] {
        var result: [KnowledgeReference] = []
        var start = text.startIndex
        var offset = 0
        var line = 1
        while start < text.endIndex {
            let limit = text.index(start, offsetBy: 1_200, limitedBy: text.endIndex) ?? text.endIndex
            let end: String.Index
            if limit < text.endIndex, let newline = text[start..<limit].lastIndex(of: "\n") {
                end = text.index(after: newline)
            } else { end = limit }
            let snippet = String(text[start..<end])
            result.append(KnowledgeReference(id: UUID(), documentID: document.id, title: document.title, importedAt: document.importedAt,
                                             startLine: line, characterOffset: offset, snippet: snippet))
            offset += snippet.count
            line += snippet.filter { $0 == "\n" }.count
            start = end
        }
        return result
    }
}

// Confined to KnowledgeIndex's actor; the connection never escapes to UI callers.
private final class KnowledgeDatabase {
    private var handle: OpaquePointer?

    init() throws {
        guard sqlite3_open(":memory:", &handle) == SQLITE_OK else {
            sqlite3_close(handle)
            throw KnowledgeFailure.search
        }
        do { try execute("CREATE VIRTUAL TABLE chunks USING fts5(id UNINDEXED, document UNINDEXED, words)") } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String, _ values: [String] = []) throws {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw KnowledgeFailure.search }
    }

    func query(_ sql: String, _ values: [String]) throws -> [String] {
        let statement = try prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 0) { result.append(String(cString: value)) }
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw KnowledgeFailure.search }
        return result
    }

    private func prepare(_ sql: String, _ values: [String]) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            throw KnowledgeFailure.search
        }
        for (index, value) in values.enumerated() {
            let code = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard code == SQLITE_OK else { sqlite3_finalize(statement); throw KnowledgeFailure.search }
        }
        return statement
    }
}
