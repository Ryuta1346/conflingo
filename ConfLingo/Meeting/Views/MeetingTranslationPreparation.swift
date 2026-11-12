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

    var body: some View {
        if let entry = translations.entries[eventID] {
            VStack(alignment: .leading, spacing: 6) {
                Text("訳文 · \(LanguageCatalog.displayName(for: entry.request.targetLanguage))")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if let translation = entry.translation {
                    Text(translation.text).font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled)
                } else {
                    switch entry.state {
                    case .pending: Text("翻訳待ち（初回はモデルを準備）").font(.caption).foregroundStyle(DesignTokens.secondary)
                    case .translating: Text("翻訳中…").font(.caption).foregroundStyle(DesignTokens.secondary)
                    case .failed(let reason):
                        Text(reason).font(.caption).foregroundStyle(DesignTokens.warning)
                        Button("翻訳を再試行") { translations.retry(eventID) }
                    case .done: EmptyView()
                    }
                }
            }
        }
    }
}
