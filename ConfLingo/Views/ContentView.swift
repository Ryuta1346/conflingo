import SwiftUI
import Translation

struct ContentView: View {
    @State private var store = SessionStore()
    @State private var coordinator = TranslationCoordinator()
    @State private var availability = ModelAvailabilityService()
    @State private var controller = SessionController()
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var profileStore = KeywordProfileStore()
    @State private var renameTarget: KeywordProfile?
    @State private var renameText = ""
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("sourceLocaleID") private var sourceLocaleID = "en-US"
    @AppStorage("targetLanguageID") private var targetLanguageID = "ja"
    @AppStorage("transcriptionOnly") private var transcriptionOnly = false
    @AppStorage("fastFinalization") private var fastFinalization = false

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
        .task(id: "\(sourceLocaleID)->\(targetLanguageID)|only=\(transcriptionOnly)") {
            // 起動時・言語ペア変更時・文字起こしのみモード切替時に利用可能性を再チェックする
            translationConfiguration = nil
            await availability.checkAndPrepare(
                sourceLocaleID: sourceLocaleID,
                targetLanguageID: transcriptionOnly ? nil : targetLanguageID
            )
            if transcriptionOnly {
                // 消費されないキューにバッファが溜まらないよう finish し、以降の enqueue を no-op にする
                coordinator.finish()
            } else if availability.state == .ready {
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
            for unit in await store.untranslatedUnits {
                await coordinator.enqueue(id: unit.id, text: unit.english)
            }
            // session は隔離ドメインを跨げないため、翻訳ループはこの場で回す。
            // 個別の翻訳失敗は failed を記録して続行する（セッションは落とさない）。
            for await item in stream {
                await store.beginTranslating(item.id)
                do {
                    // 専門用語をプレースホルダで保護してから翻訳し、訳文で原文表記（または指定訳語）に復元する
                    let glossary = await store.activeGlossary
                    let (masked, mapping) = TermProtector.mask(item.text, glossary: glossary)
                    let response = try await session.translate(masked)
                    let unmasked = TermProtector.unmask(response.targetText, mapping: mapping)
                    var japanese = unmasked.text
                    if !unmasked.unresolvedTokens.isEmpty,
                       let retry = try? await session.translate(item.text) {
                        // プレースホルダが復元不能に崩れた場合はマスクなしで再翻訳する
                        // （用語保護より「壊れたトークンを表示しない」ことを優先。再翻訳も失敗なら寛容パス適用済みを採用）
                        japanese = retry.targetText
                    }
                    await store.applyTranslation(id: item.id, japanese: japanese)
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

            if transcriptionOnly {
                TranscriptPane(
                    title: "\(LanguageCatalog.displayName(for: sourceLocaleID))（認識）",
                    entries: sourceEntries,
                    fontSize: fontSize
                )
            } else {
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

                if !transcriptionOnly {
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
                }

                Toggle("文字起こしのみ", isOn: $transcriptionOnly)
                    .toggleStyle(.checkbox)

                if transcriptionOnly {
                    // 議事録用途は精度優先（OFF）、リアルタイム字幕用途は速度優先（ON）
                    Toggle("高速確定（精度低め）", isOn: $fastFinalization)
                        .toggleStyle(.checkbox)
                }

                Spacer()
            }
            .disabled(store.phase != .idle)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "character.magnify")
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    // 用語辞書プロファイルの選択・管理
                    HStack(spacing: 8) {
                        Picker("用語辞書", selection: profileSelectionBinding) {
                            ForEach(profileStore.profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 220)

                        Button {
                            renameText = profileStore.selectedProfile.name
                            renameTarget = profileStore.selectedProfile
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .help("名前を変更")

                        Button {
                            profileStore.addProfile(name: "新しい辞書")
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("新規作成")

                        Button {
                            profileStore.duplicate(profileStore.selectedID)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .help("複製")

                        Button {
                            profileStore.delete(profileStore.selectedID)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("削除")
                        .disabled(profileStore.profiles.count <= 1)
                    }

                    TextField(
                        "専門用語（カンマ区切り）。「term=訳語」で訳語を固定できます（例: evals=評価）。未指定は原文表記のまま保持",
                        text: selectedKeywordsBinding,
                        axis: .vertical
                    )
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                }
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
                targetLanguage: transcriptionOnly ? nil : targetLanguageID,
                fastResults: transcriptionOnly && fastFinalization,
                contextKeywords: selectedKeywordsBinding,
                fontSize: $fontSize
            )
        }
        .alert(
            "用語辞書の名前を変更",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("名前", text: $renameText)
            Button("変更") {
                if let target = renameTarget {
                    profileStore.rename(target.id, to: renameText)
                }
                renameTarget = nil
            }
            Button("キャンセル", role: .cancel) { renameTarget = nil }
        }
    }

    /// 選択中プロファイルの keywords を双方向編集する Binding。
    /// set で1文字ごとにストアへ即書き戻すため、切替時に未保存差分は発生しない。
    private var selectedKeywordsBinding: Binding<String> {
        Binding(
            get: { profileStore.selectedProfile.keywords },
            set: { profileStore.updateSelectedKeywords($0) }
        )
    }

    /// プロファイル選択 Picker 用の Binding。
    private var profileSelectionBinding: Binding<UUID> {
        Binding(
            get: { profileStore.selectedID },
            set: { profileStore.select($0) }
        )
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
        var entries = store.units.map { unit in
            let text: String
            let dimmed: Bool
            switch unit.translationState {
            case .done:
                text = unit.japanese ?? ""
                dimmed = false
            case .failed:
                text = "（翻訳に失敗しました）"
                dimmed = true
            case .pending, .translating:
                text = "…翻訳中"
                dimmed = true
            }
            return TranscriptPane.Entry(id: unit.id.uuidString, text: text, dimmed: dimmed)
        }
        if !store.bufferedSegmentIDs.isEmpty {
            // 文末待ちでまだ翻訳単位になっていないセグメントがあることを示す
            entries.append(TranscriptPane.Entry(id: "buffered", text: "…翻訳中", dimmed: true))
        }
        return entries
    }
}

#Preview {
    ContentView()
}
