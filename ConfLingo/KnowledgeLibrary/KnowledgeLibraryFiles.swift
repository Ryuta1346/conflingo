import Darwin
import Foundation

actor KnowledgeLibraryFiles {
    struct Limits: Sendable {
        var items = 100
        var bytes = 200 * 1_048_576
        var itemBytes = 64 * 1_048_576
    }
    let directory: URL
    private let limits: Limits
    private let write: @Sendable (Data, URL) throws -> Void
    private let remove: @Sendable (URL) throws -> Void

    init(directory: URL, limits: Limits = Limits(),
         write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
         remove: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.directory = directory
        self.limits = limits
        self.write = write
        self.remove = remove
    }

    func list() throws -> [KnowledgeLibraryEntry] {
        try urls().map { url in
            let id = try identifier(url)
            do { return try load(id).entry } catch {
                return KnowledgeLibraryEntry(id: id, revision: nil, title: "読み込めない資料 · \(id.uuidString.prefix(8))",
                    kind: "不明", count: 0, updatedAt: nil, failure: error.localizedDescription)
            }
        }.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    func load(_ id: UUID) throws -> SavedKnowledge {
        try checkDirectory()
        let fd = open(path(id).path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard fd >= 0 else { throw LibraryFailure.unsafe }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0, info.st_size <= limits.itemBytes else { throw LibraryFailure.unsafe }
        let data = try handle.read(upToCount: limits.itemBytes + 1) ?? Data()
        guard data.count <= limits.itemBytes else { throw LibraryFailure.limit }
        struct Header: Decodable { let version: Int }
        guard try JSONDecoder().decode(Header.self, from: data).version == 1 else { throw LibraryFailure.unsupported }
        let saved = try JSONDecoder().decode(SavedKnowledge.self, from: data)
        guard saved.id == id else { throw LibraryFailure.invalid }
        try saved.validate()
        return saved
    }

    @discardableResult
    func save(_ content: KnowledgeArchive, title: String, replacing id: UUID? = nil,
              expectedRevision: UUID? = nil, now: Date = Date()) throws -> SavedKnowledge {
        try content.validate()
        let existing = try id.map { try load($0) }
        if let existing {
            guard existing.revision == expectedRevision, existing.content.isRepository == content.isRepository else {
                throw LibraryFailure.changed
            }
        }
        if let existing, existing.content == content, existing.title == title.trimmingCharacters(in: .whitespacesAndNewlines) { return existing }
        let saved = SavedKnowledge(version: 1, id: id ?? UUID(), revision: UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: existing?.createdAt ?? now,
            updatedAt: now, content: content)
        try saved.validate()
        let data = try JSONEncoder().encode(saved)
        guard data.count <= limits.itemBytes else { throw LibraryFailure.limit }
        let current = try urls()
        guard current.count + (existing == nil ? 1 : 0) <= limits.items else { throw LibraryFailure.limit }
        var bytes = data.count
        for url in current where url.lastPathComponent != path(saved.id).lastPathComponent {
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_size >= 0 else { throw LibraryFailure.unsafe }
            guard info.st_size <= limits.bytes, bytes <= limits.bytes - Int(info.st_size) else { throw LibraryFailure.limit }
            bytes += Int(info.st_size)
        }
        guard bytes <= limits.bytes else { throw LibraryFailure.limit }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try checkDirectory()
        try write(data, path(saved.id))
        return saved
    }

    func delete(_ id: UUID) throws {
        try checkDirectory()
        var info = stat()
        guard lstat(path(id).path, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG || info.st_mode & S_IFMT == S_IFLNK else { throw LibraryFailure.unsafe }
        try remove(path(id))
    }

    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func identifier(_ url: URL) throws -> UUID {
        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { throw LibraryFailure.invalid }
        return id
    }
    private func urls() throws -> [URL] {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            if errno == ENOENT { return [] }
            throw LibraryFailure.unsafe
        }
        try checkDirectory()
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
    }
    private func checkDirectory() throws {
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else { throw LibraryFailure.unsafe }
    }
}
