import Foundation
import Testing
@testable import ConfLingo

private final class PersistenceGoldenBundleToken: NSObject {}

enum PersistenceGoldenFixture {
    static let sessionNames = ["r3-meeting-basic", "r3-meeting-extended", "r3-conference-basic", "r3-conference-extended"]
    static let knowledgeNames = ["r3-knowledge-document", "r3-knowledge-repository"]
    static let createdAt = Date(timeIntervalSinceReferenceDate: 100)
    static let updatedAt = Date(timeIntervalSinceReferenceDate: 200)

    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: PersistenceGoldenBundleToken.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    static func id(_ number: Int) throws -> UUID {
        try #require(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number)))
    }

    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PersistenceGolden-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func path(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent(id.uuidString + ".json")
    }

    static func canonical(_ data: Data) throws -> Data {
        try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys])
    }

    static func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
