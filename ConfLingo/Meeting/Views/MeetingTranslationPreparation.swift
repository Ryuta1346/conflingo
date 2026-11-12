import SwiftUI
import Translation

struct MeetingTranslationPreparation: View {
    let translations: MeetingTranslations

    var body: some View {
        if translations.requiresPreparation {
            ForEach(translations.lanes) { lane in
                MeetingLanguagePreparation(translations: translations, laneID: lane.id,
                    generation: lane.generation, source: lane.sourceLanguage, target: lane.targetLanguage)
                    .id(lane.generation)
            }
        }
    }
}

private struct MeetingLanguagePreparation: View {
    let translations: MeetingTranslations
    let laneID: UUID
    let generation: UUID
    let source: String
    let target: String

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .translationTask(TranslationSession.Configuration(source: Locale.Language(identifier: source),
                                                              target: Locale.Language(identifier: target))) { @Sendable session in
                do {
                    let availability = LanguageAvailability()
                    let status = await availability.status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target))
                    guard status != .unsupported else {
                        await translations.preparationFailed(laneID, generation: generation, message: "この言語の組み合わせは翻訳に対応していません。")
                        return
                    }
                    try await session.prepareTranslation()
                    try Task.checkCancellation()
                    await translations.prepared(laneID, generation: generation)
                } catch {
                    await translations.preparationFailed(laneID, generation: generation,
                        message: "翻訳モデルを準備できませんでした。文字起こしは継続します。\(error.localizedDescription)")
                }
            }
            .accessibilityHidden(true)
    }
}

struct MeetingTranslationText: View {
    let translations: MeetingTranslations
    let eventID: UUID
    let fontSize: Double
    var sourceText = ""
    var targetLanguage: String?

    private var entry: MeetingTranslationEntry? { translations.entries[eventID] }

    var body: some View {
        if let target = entry?.request.targetLanguage ?? targetLanguage {
            VStack(alignment: .leading, spacing: 6) {
                Text("訳文 · \(LanguageCatalog.displayName(for: target))")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                ReservedTranslation(sourceText: entry?.request.event.text ?? sourceText, fontSize: fontSize) {
                    if let translation = entry?.translation {
                        Text(translation.text).font(.system(size: fontSize)).lineSpacing(6).textSelection(.enabled)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            switch entry?.state {
                            case .pending: Text("翻訳待ち（初回はモデルを準備）")
                            case .translating: Text("翻訳中…")
                            case .failed(let reason):
                                Text(reason).foregroundStyle(DesignTokens.warning)
                                Button("翻訳を再試行") { translations.retry(eventID) }
                            case .done: Text("翻訳完了")
                            case nil: Text("発話の確定待ち")
                            }
                        }
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    }
                }
            }
        }
    }
}
