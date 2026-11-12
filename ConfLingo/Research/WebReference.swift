import Foundation

struct WebReference: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let url: URL
    let title: String
    let fetchedAt: Date

    static func validURL(_ url: URL) -> Bool {
        ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
            && url.user == nil && url.password == nil && url.absoluteString.count <= 4_096
    }
}
