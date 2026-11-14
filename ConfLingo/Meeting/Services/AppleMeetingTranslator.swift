import Foundation
import Translation

protocol MeetingTranslationBackend {
    func translate(_ text: String) async throws -> TranslationSession.Response
}

extension TranslationSession: MeetingTranslationBackend {}

struct AppleMeetingTranslator: MeetingTranslating {
    private let makeBackend: @Sendable (String, String) -> any MeetingTranslationBackend

    init(makeBackend: @escaping @Sendable (String, String) -> any MeetingTranslationBackend = {
        TranslationSession(installedSource: Locale.Language(identifier: $0), target: Locale.Language(identifier: $1))
    }) {
        self.makeBackend = makeBackend
    }

    @concurrent
    func run(_ ids: AsyncStream<UUID>, source: String, target: String,
             begin: @escaping MeetingTranslationBegin, complete: @escaping MeetingTranslationComplete) async {
        guard !Task.isCancelled else { return }
        // TranslationSession is non-Sendable; keep it in this worker for the entire language pair.
        let backend = makeBackend(source, target)
        await processMeetingTranslations(ids, begin: begin, complete: complete) { request in
            return try await backend.translate(request.text).targetText
        }
    }
}
