import Foundation
// Only the configuration/value types needed by the unmodified presentation sources.
enum SessionMode { case transcription }
enum TranslationCoordinator {
    enum PreparationState: Equatable { case idle, preparing, ready, failed(String) }
}
struct ConferenceCorrection: Equatable {
    let unitID: UUID
    let sourceText: String
    let translation: String?
    let adopted: Bool
}
