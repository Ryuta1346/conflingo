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
        guard body.count <= 100_000, documents.filter({ $0.source == nil }).count < 20,
              documents.filter({ $0.source == nil }).reduce(0, { $0 + $1.characterCount }) + body.count <= 500_000 else { throw KnowledgeFailure.limit }
        guard !documents.filter({ $0.source == nil }).contains(where: { bodies[$0.id] == body }) else { throw KnowledgeFailure.duplicate }
        let document = KnowledgeDocument(id: UUID(), title: String((filename as NSString).lastPathComponent.prefix(200)),
                                         importedAt: Date(), characterCount: body.count)
        let references = Self.split(body, document: document)
        let database = try connection()
        try database.execute("BEGIN")
        do {
            for reference in references {
                try Task.checkCancellation()
                try database.execute("INSERT INTO chunks(id, document, paths, words) VALUES (?, ?, ?, ?)",
                                     [reference.id.uuidString, document.id.uuidString, "", Self.words(reference.snippet).joined(separator: " ")])
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

    func addRepository(_ snapshot: RepositorySnapshot) throws -> [KnowledgeDocument] {
        guard !documents.contains(where: { $0.source != nil }) else { throw KnowledgeFailure.duplicate }
        guard !snapshot.files.isEmpty, snapshot.files.count <= 1_000,
              snapshot.files.reduce(0, { $0 + $1.body.count }) <= 5_000_000 else { throw RepositoryFailure.limit }
        var pending: [(KnowledgeDocument, String, [KnowledgeReference])] = []
        let database = try connection()
        try database.execute("BEGIN")
        do {
            for file in snapshot.files {
                try Task.checkCancellation()
                let source = RepositorySource(snapshotID: snapshot.id, name: snapshot.name, path: file.path, contentHash: file.hash)
                let document = KnowledgeDocument(id: UUID(), title: String((file.path as NSString).lastPathComponent.prefix(200)),
                                                 importedAt: snapshot.importedAt, characterCount: file.body.count, source: source)
                let references = Self.split(file.body, document: document)
                for reference in references {
                    try Task.checkCancellation()
                    try database.execute("INSERT INTO chunks(id, document, paths, words) VALUES (?, ?, ?, ?)",
                                         [reference.id.uuidString, document.id.uuidString, Self.words(file.path).joined(separator: " "),
                                          Self.words(reference.snippet).joined(separator: " ")])
                }
                pending.append((document, file.body, references))
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
        for (document, body, references) in pending {
            documents.append(document)
            bodies[document.id] = body
            for reference in references { chunks[reference.id] = reference }
        }
        return pending.map { $0.0 }
    }

    func archive(documentID: UUID?) throws -> KnowledgeArchive {
        let selected = documents.filter { doc in documentID.map { doc.id == $0 && doc.source == nil } ?? (doc.source != nil) }
        let archive = KnowledgeArchive(documents: try selected.map { doc in
            guard let body = bodies[doc.id] else { throw LibraryFailure.invalid }
            return .init(document: doc, body: body)
        })
        try archive.validate()
        return archive
    }

    func contents() -> [KnowledgeArchive.Document] {
        documents.compactMap { document in bodies[document.id].map { .init(document: document, body: $0) } }
    }

    func restore(_ archive: KnowledgeArchive) throws -> [KnowledgeDocument] {
        try Task.checkCancellation()
        try archive.validate()
        if archive.isRepository {
            guard !documents.contains(where: { $0.source != nil }) else { throw LibraryFailure.duplicate }
        } else {
            let existing = documents.filter { $0.source == nil }
            guard existing.count < 20, existing.reduce(0, { $0 + $1.characterCount }) + archive.documents[0].body.count <= 500_000 else {
                throw KnowledgeFailure.limit
            }
            guard !existing.contains(where: { bodies[$0.id] == archive.documents[0].body }) else { throw KnowledgeFailure.duplicate }
        }
        guard Set(documents.map(\.id)).isDisjoint(with: archive.documents.map { $0.document.id }) else { throw LibraryFailure.duplicate }
        let pending = archive.documents.map { ($0, Self.split($0.body, document: $0.document)) }
        let database = try connection()
        try database.execute("BEGIN")
        do {
            for (item, references) in pending {
                for reference in references {
                    try Task.checkCancellation()
                    try database.execute("INSERT INTO chunks(id, document, paths, words) VALUES (?, ?, ?, ?)",
                        [reference.id.uuidString, item.document.id.uuidString,
                         Self.words(item.document.source?.path ?? "").joined(separator: " "), Self.words(reference.snippet).joined(separator: " ")])
                }
            }
            try Task.checkCancellation()
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
        for (item, references) in pending {
            documents.append(item.document)
            bodies[item.document.id] = item.body
            for reference in references { chunks[reference.id] = reference }
        }
        return archive.documents.map(\.document)
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

    func removeRepository() throws {
        let ids = Set(documents.filter { $0.source != nil }.map(\.id))
        let database = try connection()
        try database.execute("BEGIN")
        do {
            for id in ids { try database.execute("DELETE FROM chunks WHERE document = ?", [id.uuidString]) }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
        documents.removeAll { ids.contains($0.id) }
        for id in ids { bodies[id] = nil }
        chunks = chunks.filter { !ids.contains($0.value.documentID) }
    }

    func search(_ query: String) throws -> [KnowledgeReference] {
        try Task.checkCancellation()
        let terms = Self.words(String(query.prefix(2_000))).filter { !Self.stopWords.contains($0) }
        guard !terms.isEmpty else { return [] }
        var seen: Set<String> = []
        let expression = terms.filter { seen.insert($0).inserted }.prefix(32).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            .joined(separator: " OR ")
        let ids = try connection().query("SELECT id FROM chunks WHERE chunks MATCH ? ORDER BY bm25(chunks, 0, 0, 5, 1), rowid LIMIT 10", [expression])
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
        let expanded = text.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
        let text = expanded == text ? text : text + " " + expanded
        let tokenizer = NLTokenizer(unit: .word)
        var words: [String] = []
        for part in text.split(whereSeparator: { $0.isWhitespace }) {
            let text = String(part)
            tokenizer.string = text
            var ranges = tokenizer.tokens(for: text.startIndex..<text.endIndex)
            // Ambiguous short kanji terms such as 月額 can otherwise become isolated characters.
            if ranges.count > 1 && ranges.allSatisfy({ range in
                let scalars = text[range].unicodeScalars
                return scalars.count == 1 && scalars.first?.properties.isIdeographic == true
            }) {
                let japanese = NLTokenizer(unit: .word)
                japanese.setLanguage(.japanese)
                japanese.string = text
                ranges = japanese.tokens(for: text.startIndex..<text.endIndex)
            }
            for range in ranges {
                let word = String(text[range]).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                if word.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) { words.append(word) }
            }
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
                                             startLine: line, characterOffset: offset, snippet: snippet, source: document.source))
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
        do { try execute("CREATE VIRTUAL TABLE chunks USING fts5(id UNINDEXED, document UNINDEXED, paths, words)") } catch {
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
