import Foundation

enum TranslationState: Equatable, Sendable {
    case pending
    case translating
    case done
    case failed(String)
}

struct TranscriptSegment: Identifiable, Equatable, Sendable {
    let id: UUID
    let index: Int
    let english: String
    var japanese: String?
    var translationState: TranslationState
    let finalizedAt: Date
}
