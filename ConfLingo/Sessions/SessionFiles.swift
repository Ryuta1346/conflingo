import Foundation

enum SessionFileError: Error, LocalizedError {
    case invalid, unsupported, unsafe
    var errorDescription: String? {
        switch self {
        case .invalid: "保存データを読み込めません。内容や参照が不正です。元のファイルは保持しています。"
        case .unsupported: "この保存形式には対応していません。元のファイルは保持しています。"
        case .unsafe: "保存先にアクセスできません。ファイルとアクセス権を確認してください。"
        }
    }
}

actor SessionFiles {
    let directory: URL
    private let write: @Sendable (Data, URL) throws -> Void
    private let remove: @Sendable (URL) throws -> Void

    init(directory: URL,
         write: @escaping @Sendable (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
         remove: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.directory = directory
        self.write = write
        self.remove = remove
    }

    func list() throws -> [SessionListEntry] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        try checkDirectory()
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return urls.compactMap { url -> SessionListEntry? in
            guard url.pathExtension == "json", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else { return nil }
            do {
                let saved = try load(id)
                return SessionListEntry(id: id, title: saved.snapshot.title, kind: saved.snapshot.kind,
                                        startedAt: saved.snapshot.startedAt, updatedAt: saved.updatedAt, failure: nil)
            } catch {
                return SessionListEntry(id: id, title: "読み込めないセッション · \(id.uuidString.prefix(8))", kind: "不明",
                                        startedAt: nil, updatedAt: nil, failure: error.localizedDescription)
            }
        }.sorted {
            if $0.updatedAt == $1.updatedAt { return $0.id.uuidString < $1.id.uuidString }
            return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
        }
    }

    func load(_ id: UUID) throws -> SavedSession {
        try checkDirectory()
        let url = path(id)
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw SessionFileError.unsafe }
        let data = try Data(contentsOf: url)
        struct Header: Decodable { let version: Int }
        guard try JSONDecoder().decode(Header.self, from: data).version == 1 else { throw SessionFileError.unsupported }
        let saved = try JSONDecoder().decode(SavedSession.self, from: data)
        guard saved.id == id, saved.createdAt.timeIntervalSince1970.isFinite, saved.updatedAt.timeIntervalSince1970.isFinite else {
            throw SessionFileError.invalid
        }
        try saved.snapshot.validate()
        return saved
    }

    @discardableResult
    func save(_ snapshot: SessionSnapshot, now: Date = Date()) throws -> SavedSession {
        try snapshot.validate()
        guard now.timeIntervalSince1970.isFinite else { throw SessionFileError.invalid }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try checkDirectory()
        let url = path(snapshot.id)
        let existing = FileManager.default.fileExists(atPath: url.path) ? try load(snapshot.id) : nil
        let saved = SavedSession(version: 1, createdAt: existing?.createdAt ?? now, updatedAt: now, snapshot: snapshot)
        let data = try JSONEncoder().encode(saved)
        try write(data, url)
        return saved
    }

    func delete(_ id: UUID) throws {
        try checkDirectory()
        try remove(path(id))
    }

    private func path(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    private func checkDirectory() throws {
        let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw SessionFileError.unsafe }
    }
}
