import CryptoKit
import Darwin
import Foundation

struct RepositoryLimits: Sendable {
    var files = 1_000
    var characters = 5_000_000
    var bytes = 20 * 1_048_576
    var entries = 20_000
    var depth = 32
}

struct RepositorySource: Equatable, Sendable {
    let snapshotID: UUID
    let name: String
    let path: String
    let contentHash: String

    var description: String { "\(name)/\(path) · 作業ツリー \(contentHash.prefix(12))" }
}

struct RepositoryEntry: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let bytes: Int
    let stamp: String
    let reason: String?
}

struct RepositoryScan: Identifiable, Sendable {
    let id = UUID()
    let root: URL
    let rootIdentity: String
    let entries: [RepositoryEntry]
    var eligible: [RepositoryEntry] { entries.filter { $0.reason == nil } }
}

struct RepositorySnapshot: Sendable {
    let id: UUID
    let name: String
    let importedAt: Date
    let files: [File]
    struct File: Sendable {
        let path: String
        let body: String
        let hash: String
    }
}

enum RepositoryFailure: Error, LocalizedError {
    case unreadable, changed, selection, limit, encoding
    var errorDescription: String? {
        switch self {
        case .unreadable: "フォルダやファイルを安全に読み込めません。リンク、権限、ファイル種別を確認してください。"
        case .changed: "対象が確認時から変更されました。フォルダを選び直してください。"
        case .selection: "取り込むファイルを対象一覧から選択してください。"
        case .limit: "リポジトリの上限を超えています。対象を絞ってください（1,000ファイル・500万文字・20 MiB、1件1 MiB・10万文字）。"
        case .encoding: "空のファイル、またはUTF-8テキストとして読めないファイルがあります。対象から外してください。"
        }
    }
}

enum RepositoryImporter {
    static func scan(_ root: URL, limits: RepositoryLimits = RepositoryLimits()) async throws -> RepositoryScan {
        let task = Task.detached { try scanFiles(root, limits: limits) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    static func load(_ scan: RepositoryScan, selected: Set<String>, limits: RepositoryLimits = RepositoryLimits()) async throws -> RepositorySnapshot {
        let task = Task.detached { try loadFiles(scan, selected: selected, limits: limits) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    private static let extensions: Set<String> = Set("swift m mm h c cc cpp hpp rs go java kt kts py rb php js jsx ts tsx vue svelte html css scss sql sh md txt json yaml yml toml xml plist".split(separator: " ").map(String.init))
    private static let directories: Set<String> = ["node_modules", "vendor", "build", "dist", "deriveddata", "pods", "carthage", "__pycache__", "coverage", "target"]
    private static let secrets: Set<String> = ["credentials.json", "credentials.yaml", "credentials.yml", "secrets.json", "secrets.yaml", "secrets.yml", "id_rsa", "id_ed25519"]

    private static func openRoot(_ root: URL) throws -> Int32 {
        guard root.isFileURL else { throw RepositoryFailure.unreadable }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw RepositoryFailure.unreadable }
        return fd
    }

    private static func identity(_ fd: Int32) throws -> String {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw RepositoryFailure.unreadable }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private static func stamp(_ info: stat) -> String {
        "\(info.st_dev):\(info.st_ino):\(info.st_size):\(info.st_mtimespec.tv_sec):\(info.st_mtimespec.tv_nsec):\(info.st_ctimespec.tv_sec):\(info.st_ctimespec.tv_nsec)"
    }

    private static func scanFiles(_ root: URL, limits: RepositoryLimits) throws -> RepositoryScan {
        let scoped = root.startAccessingSecurityScopedResource()
        defer { if scoped { root.stopAccessingSecurityScopedResource() } }
        let fd = try openRoot(root)
        defer { close(fd) }
        var entries: [RepositoryEntry] = []
        func walk(_ directory: Int32, prefix: String, depth: Int) throws {
            guard depth <= limits.depth else { throw RepositoryFailure.limit }
            let copy = dup(directory)
            guard copy >= 0 else { throw RepositoryFailure.unreadable }
            guard let stream = fdopendir(copy) else { close(copy); throw RepositoryFailure.unreadable }
            defer { closedir(stream) }
            while true {
                try Task.checkCancellation()
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw RepositoryFailure.unreadable }
                    break
                }
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name == "." || name == ".." { continue }
                guard entries.count < limits.entries else { throw RepositoryFailure.limit }
                let path = prefix + name
                var info = stat()
                guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw RepositoryFailure.unreadable }
                let type = info.st_mode & S_IFMT
                let lower = name.lowercased()
                var reason: String?
                if name.hasPrefix(".") { reason = "隠しファイル/フォルダ" }
                else if type == S_IFLNK { reason = "リンク" }
                else if path.count > 1_024 { reason = "パスが長すぎます" }
                else if type == S_IFDIR && directories.contains(lower) { reason = "依存パッケージ/生成物" }
                else if secrets.contains(lower) || lower.hasPrefix(".env") || ["pem", "key", "p12", "pfx", "cer"].contains((lower as NSString).pathExtension) { reason = "認証情報" }
                else if lower.hasSuffix(".lock") || ["package-lock.json", "yarn.lock", "pnpm-lock.yaml", "package.resolved"].contains(lower) || lower.contains(".min.") { reason = "lockfile/生成物" }
                else if type == S_IFREG && !extensions.contains((lower as NSString).pathExtension) && !["dockerfile", "makefile"].contains(lower) { reason = "未対応形式" }
                else if type != S_IFREG && type != S_IFDIR { reason = "通常ファイルではありません" }
                if type == S_IFDIR && reason == nil {
                    let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw RepositoryFailure.changed }
                    defer { close(child) }
                    var git = stat()
                    if fstatat(child, ".git", &git, AT_SYMLINK_NOFOLLOW) == 0 { reason = "入れ子のリポジトリ" }
                    else {
                        entries.append(RepositoryEntry(path: path + "/", bytes: 0, stamp: stamp(info), reason: "フォルダ"))
                        try walk(child, prefix: path + "/", depth: depth + 1)
                        continue
                    }
                }
                if reason == nil && (info.st_size > 1_048_576 || info.st_size == 0) { reason = "空または1 MiB超過" }
                entries.append(RepositoryEntry(path: path, bytes: Int(info.st_size), stamp: stamp(info), reason: reason))
            }
        }
        try walk(fd, prefix: "", depth: 0)
        return RepositoryScan(root: root, rootIdentity: try identity(fd), entries: entries.sorted { $0.path < $1.path })
    }

    private static func readFile(_ path: String, root: Int32, expected: String) throws -> Data {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !path.hasPrefix("/"), components.allSatisfy({ $0 != "." && $0 != ".." }) else { throw RepositoryFailure.selection }
        var directory = dup(root)
        guard directory >= 0 else { throw RepositoryFailure.unreadable }
        defer { close(directory) }
        for component in components.dropLast() {
            let child = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw RepositoryFailure.changed }
            close(directory)
            directory = child
            var git = stat()
            guard fstatat(directory, ".git", &git, AT_SYMLINK_NOFOLLOW) != 0 else { throw RepositoryFailure.changed }
        }
        guard let name = components.last else { throw RepositoryFailure.selection }
        let fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw RepositoryFailure.changed }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size <= 1_048_576,
              stamp(before) == expected else { throw RepositoryFailure.changed }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            let count = read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw RepositoryFailure.unreadable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= 1_048_576 else { throw RepositoryFailure.limit }
        }
        var after = stat()
        guard fstat(fd, &after) == 0, stamp(before) == stamp(after), data.count == before.st_size else { throw RepositoryFailure.changed }
        return data
    }

    private static func loadFiles(_ scan: RepositoryScan, selected: Set<String>, limits: RepositoryLimits) throws -> RepositorySnapshot {
        guard !selected.isEmpty, selected.isSubset(of: Set(scan.eligible.map(\.path))) else { throw RepositoryFailure.selection }
        guard selected.count <= limits.files else { throw RepositoryFailure.limit }
        let scoped = scan.root.startAccessingSecurityScopedResource()
        defer { if scoped { scan.root.stopAccessingSecurityScopedResource() } }
        let fd = try openRoot(scan.root)
        defer { close(fd) }
        guard try identity(fd) == scan.rootIdentity else { throw RepositoryFailure.changed }
        var files: [RepositorySnapshot.File] = []
        var bytes = 0
        var characters = 0
        for entry in scan.eligible where selected.contains(entry.path) {
            let data = try readFile(entry.path, root: fd, expected: entry.stamp)
            bytes += data.count
            guard bytes <= limits.bytes else { throw RepositoryFailure.limit }
            guard var body = String(data: data, encoding: .utf8), !body.contains("\0") else { throw RepositoryFailure.encoding }
            if body.first == "\u{feff}" { body.removeFirst() }
            body = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RepositoryFailure.encoding }
            characters += body.count
            guard body.count <= 100_000, characters <= limits.characters else { throw RepositoryFailure.limit }
            let hash = SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
            files.append(.init(path: entry.path, body: body, hash: hash))
        }
        return RepositorySnapshot(id: UUID(), name: String(scan.root.lastPathComponent.prefix(128)), importedAt: Date(), files: files)
    }
}
