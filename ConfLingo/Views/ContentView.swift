import SwiftUI
import Translation

struct ContentView: View {
    @State private var store = SessionStore()
    @State private var coordinator = TranslationCoordinator()
    @State private var availability = ModelAvailabilityService()
    @State private var controller = SessionController()
    @State private var translationConfiguration: TranslationSession.Configuration?
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("contextKeywords") private var contextKeywords = KeywordParser.defaultKeywords
    @AppStorage("sourceLocaleID") private var sourceLocaleID = "en-US"
    @AppStorage("targetLanguageID") private var targetLanguageID = "ja"

    var body: some View {
        Group {
            switch availability.state {
            case .checking, .downloadingSpeechModel:
                SetupView(availability: availability)
            case .unavailable(let reason):
                ContentUnavailableView {
                    Label("利用できません", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reason)
                }
            case .ready:
                sessionView
            }
        }
        .task(id: "\(sourceLocaleID)->\(targetLanguageID)") {
            // 起動時および言語ペア変更時に利用可能性を再チェックする
            translationConfiguration = nil
            await availability.checkAndPrepare(
                sourceLocaleID: sourceLocaleID,
                targetLanguageID: targetLanguageID
            )
            if availability.state == .ready {
                translationConfiguration = TranslationSession.Configuration(
                    source: (availability.speechLocale ?? Locale(identifier: sourceLocaleID)).language,
                    target: Locale.Language(identifier: targetLanguageID)
                )
            }
        }
        .onChange(of: sourceLocaleID) {
            // 認識言語と翻訳先が同一言語に衝突したら自動で振り替える
            targetLanguageID = LanguageCatalog.resolveTarget(
                current: targetLanguageID,
                sourceLocaleID: sourceLocaleID
            )
        }
        // @Sendable でクロージャを nonisolated にし、非 Sendable な session を
        // MainActor 領域に取り込まずタスク領域に留める（translate 呼び出しに必須）。
        .translationTask(translationConfiguration) { @Sendable session in
            do {
                try await session.prepareTranslation()
            } catch {
                // 翻訳モデルのダウンロードがキャンセルされた等。文字起こしのみで継続する。
                return
            }
            let stream = await coordinator.attach()
            for segment in await store.untranslatedSegments {
                await coordinator.enqueue(id: segment.id, text: segment.english)
            }
            // session は隔離ドメインを跨げないため、翻訳ループはこの場で回す。
            // 個別の翻訳失敗は failed を記録して続行する（セッションは落とさない）。
            for await item in stream {
                await store.beginTranslating(item.id)
                do {
                    // 専門用語をプレースホルダで保護してから翻訳し、訳文で原文表記に復元する
                    let terms = await store.activeKeywords
                    let (masked, mapping) = TermProtector.mask(item.text, terms: terms)
                    let response = try await session.translate(masked)
                    let restored = TermProtector.unmask(response.targetText, mapping: mapping)
                    await store.applyTranslation(id: item.id, japanese: restored)
                } catch {
                    await store.markTranslationFailed(id: item.id, reason: error.localizedDescription)
                }
            }
        }
    }

    private var sessionView: some View {
        VStack(spacing: 0) {
            if let error = controller.lastError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.red.opacity(0.8))
            }

            VSplitView {
                TranscriptPane(
                    title: "\(LanguageCatalog.displayName(for: sourceLocaleID))（認識）",
                    entries: sourceEntries,
                    fontSize: fontSize
                )
                TranscriptPane(
                    title: "\(LanguageCatalog.displayName(for: targetLanguageID))（翻訳）",
                    entries: targetEntries,
                    fontSize: fontSize
                )
            }

            Divider()

            HStack(spacing: 8) {
                Picker("認識", selection: $sourceLocaleID) {
                    ForEach(availability.supportedSourceLocales, id: \.identifier) { locale in
                        Text(LanguageCatalog.displayName(for: locale.identifier))
                            .tag(locale.identifier)
                    }
                }
                .frame(maxWidth: 240)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                Picker("翻訳先", selection: $targetLanguageID) {
                    ForEach(
                        LanguageCatalog.selectableTargets(
                            availability.supportedTargetLanguages,
                            excludingSourceLocaleID: sourceLocaleID
                        ),
                        id: \.minimalIdentifier
                    ) { language in
                        Text(LanguageCatalog.displayName(for: language.minimalIdentifier))
                            .tag(language.minimalIdentifier)
                    }
                }
                .frame(maxWidth: 240)

                Spacer()
            }
            .disabled(store.phase != .idle)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "character.magnify")
                    .foregroundStyle(.secondary)
                TextField(
                    "専門用語（カンマ区切り）。音声認識の精度向上に加え、翻訳でも原文表記のまま保持されます",
                    text: $contextKeywords
                )
                .textFieldStyle(.roundedBorder)
                .disabled(store.phase != .idle)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ControlBar(
                store: store,
                controller: controller,
                coordinator: coordinator,
                speechLocale: availability.speechLocale ?? Locale(identifier: sourceLocaleID),
                sourceLanguage: sourceLocaleID,
                targetLanguage: targetLanguageID,
                contextKeywords: $contextKeywords,
                fontSize: $fontSize
            )
        }
    }

    private var sourceEntries: [TranscriptPane.Entry] {
        var entries = store.segments.map {
            TranscriptPane.Entry(id: $0.id.uuidString, text: $0.english, dimmed: false)
        }
        if !store.volatileText.isEmpty {
            entries.append(TranscriptPane.Entry(id: "volatile", text: store.volatileText, dimmed: true))
        }
        return entries
    }

    private var targetEntries: [TranscriptPane.Entry] {
        store.segments.map { segment in
            let text: String
            let dimmed: Bool
            switch segment.translationState {
            case .done:
                text = segment.japanese ?? ""
                dimmed = false
            case .failed:
                text = "（翻訳に失敗しました）"
                dimmed = true
            case .pending, .translating:
                text = "…翻訳中"
                dimmed = true
            }
            return TranscriptPane.Entry(id: segment.id.uuidString, text: text, dimmed: dimmed)
        }
    }
}

#Preview {
    ContentView()
}
