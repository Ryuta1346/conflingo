import SwiftUI

struct ConferenceSetupView: View {
    @Binding var sessionName: String
    var inputSelection: Binding<AudioInputSelection> = .constant(.microphone)
    @Binding var sourceLanguage: String
    @Binding var targetLanguage: String
    @Binding var mode: SessionMode
    @Binding var fastFinalization: Bool
    @Bindable var profiles: KeywordProfileStore
    let sourceLocales: [Locale]
    let targetLanguages: [Locale.Language]
    let modelState: ModelAvailabilityService.State
    let downloadProgress: Progress?
    let canEdit: Bool
    let hasTranscript: Bool
    let editDictionary: () -> Void
    let retry: () -> Void
    let openTranscript: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "字幕の準備", subtitle: "聴きたい言語と、読みたい言語を選びます。")
                modelStatus
                Surface {
                    VStack(alignment: .leading, spacing: 20) {
                        labeledField("セッション名") {
                            TextField("例：WWDC セッション", text: $sessionName)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("セッション名")
                        }
                        AudioInputPicker(selection: inputSelection).disabled(!canEdit)
                        SessionModePicker(selection: $mode).disabled(!canEdit)
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 24) { languageFields }
                            VStack(alignment: .leading, spacing: 18) { languageFields }
                        }
                        .disabled(!canEdit)
                        if mode == .transcription {
                            Toggle("高速確定（精度より字幕の速さを優先）", isOn: $fastFinalization)
                                .disabled(!canEdit)
                        }
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("専門用語辞書").font(.headline)
                                Text("固有名詞や訳語を、いつもの表記で。")
                                    .font(.callout).foregroundStyle(DesignTokens.secondary)
                            }
                            Spacer()
                            Button("辞書を管理", systemImage: "book", action: editDictionary)
                                .disabled(!canEdit)
                        }
                        Picker("使用する辞書", selection: Binding(
                            get: { profiles.selectedID }, set: { profiles.select($0) }
                        )) {
                            ForEach(profiles.profiles) { Text($0.name).tag($0.id) }
                        }
                        .disabled(!canEdit)
                        Text(profiles.selectedProfile.keywords.isEmpty ? "登録された用語はありません" : profiles.selectedProfile.keywords)
                            .font(.callout).foregroundStyle(DesignTokens.secondary)
                            .lineLimit(3)
                        if hasTranscript {
                            Divider()
                            Button("現在の字幕を開く", systemImage: "captions.bubble", action: openTranscript)
                        }
                    }
                }
                Label("音声認識と翻訳はこのMacで行います。字幕は自動保存されません。", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(DesignTokens.secondary)
            }
            .padding(28)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var languageFields: some View {
        labeledField("認識する言語") {
            Picker("認識する言語", selection: $sourceLanguage) {
                ForEach(sourceLocales, id: \.identifier) {
                    Text(LanguageCatalog.displayName(for: $0.identifier)).tag($0.identifier)
                }
            }
            .labelsHidden()
        }
        if mode == .translation {
            labeledField("翻訳先") {
                Picker("翻訳先", selection: $targetLanguage) {
                    ForEach(LanguageCatalog.selectableTargets(targetLanguages, excludingSourceLocaleID: sourceLanguage), id: \.minimalIdentifier) {
                        Text(LanguageCatalog.displayName(for: $0.minimalIdentifier)).tag($0.minimalIdentifier)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.callout.weight(.medium))
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var modelStatus: some View {
        switch modelState {
        case .ready:
            StatusLabel(text: "認識モデルの準備完了", symbol: "checkmark.circle", color: DesignTokens.positive)
        case .checking, .downloadingSpeechModel:
            SetupView(state: modelState, progress: downloadProgress, sourceLanguage: sourceLanguage)
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 10) {
                SessionErrorBanner(message: reason)
                Button("もう一度確認", systemImage: "arrow.clockwise", action: retry).disabled(!canEdit)
            }
        }
    }
}
