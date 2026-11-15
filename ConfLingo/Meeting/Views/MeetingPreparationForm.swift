import AppKit
import SwiftUI

struct MeetingPreparationForm: View {
    @Bindable var meeting: MeetingWorkspace
    var models: any ModelPreparing = SystemModelPreparation()
    var vocabularyModels: any ModelPreparing = VocabularyModelPreparation()
    @State private var locales: [Locale] = []
    @State private var targets: [Locale.Language] = []
    @State private var loaded = false

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 18) {
                field("会議名") {
                    TextField("例：チームの定例会議", text: $meeting.name)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("会議名")
                }
                AudioInputPicker(selection: $meeting.inputSelection)
                SessionModePicker(selection: $meeting.mode)
                ForEach([AudioOrigin.microphone, .systemAudio].filter { meeting.inputSelection.origins.contains($0) }, id: \.self) { origin in
                    languageFields(origin)
                }
                if meeting.mode == .translation {
                    Text("確定した原文の下に訳文を表示します。同じ言語は翻訳せず、原文を表示します。翻訳先の変更は次の開始以降に適用します。")
                        .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                }
                if meeting.inputSelection.origins.contains(.systemAudio) {
                    Text("内部音声にはMacで再生する他の音も含まれます。ヘッドフォンの利用を推奨します。")
                        .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary)
                }
                Divider()
                Toggle("参加者に文字起こしを通知し、同意を確認しました", isOn: $meeting.consentConfirmed)
                Text("このチェックで参加者への通知が送信されることはありません。")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)
            }.disabled(meeting.phase != .idle || meeting.isBusy)
        }
        .task(id: meeting.recognitionMode) {
            loaded = false
            let backend = meeting.recognitionMode == .vocabulary ? vocabularyModels : models
            let sources = await backend.sourceLocales()
            let translations = await backend.targetLanguages()
            guard !Task.isCancelled else { return }
            locales = sources
            targets = translations
            loaded = true
        }
    }

    private func languageFields(_ origin: AudioOrigin) -> some View {
        let microphone = origin == .microphone
        let name = microphone ? "マイク・外部入力" : "内部音声"
        let source = microphone ? $meeting.microphoneLocaleID : $meeting.systemLocaleID
        let target = microphone ? $meeting.microphoneTranslationLanguage : $meeting.systemTranslationLanguage
        let identifiers = Set(locales.map { matches($0.identifier, source.wrappedValue) ? source.wrappedValue : $0.identifier } + [source.wrappedValue]).sorted {
            LanguageCatalog.displayName(for: $0) < LanguageCatalog.displayName(for: $1)
        }
        return VStack(alignment: .leading, spacing: 12) {
            field("\(name)の認識言語") {
                Picker("\(name)の認識言語", selection: source) {
                    ForEach(identifiers, id: \.self) { identifier in
                        Text(LanguageCatalog.displayName(for: identifier)).tag(identifier)
                    }
                }.labelsHidden().disabled(!loaded || locales.isEmpty)
            }
            if !loaded {
                Text("対応する認識言語を確認中…").font(DesignTokens.Typography.supporting)
            } else if !locales.contains(where: { matches($0.identifier, source.wrappedValue) }) {
                InlineMessage(.warning, "選択中の認識言語は対応一覧にありません。対応する言語を選んでください。")
            }
            if meeting.mode == .translation {
                field("\(name)の翻訳先") {
                    Picker("\(name)の翻訳先", selection: target) {
                        Text("翻訳なし").tag("")
                        ForEach(Set(targets.map(\.minimalIdentifier) + ["ja", "en", target.wrappedValue]).filter { !$0.isEmpty }.sorted(), id: \.self) { identifier in
                            Text(LanguageCatalog.displayName(for: identifier)).tag(identifier)
                        }
                    }.labelsHidden()
                }
            }
            permission(origin)
        }
    }

    @ViewBuilder private func permission(_ origin: AudioOrigin) -> some View {
        switch meeting.controller.permissions[origin] {
        case .granted:
            Label("\(origin.label)：許可済み", systemImage: "checkmark.shield").font(DesignTokens.Typography.supporting)
        case .denied:
            InlineMessage(.warning, "\(origin.label)へのアクセスが未許可です。システム設定のプライバシーとセキュリティで許可してください。")
            Button("\(origin.label)のシステム設定を開く") {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
        case .undetermined, .unknown, nil:
            Label("\(origin.label)：開始時にアクセスを確認します", systemImage: "info.circle").font(DesignTokens.Typography.supporting)
        }
    }

    private func matches(_ left: String, _ right: String) -> Bool {
        left.replacingOccurrences(of: "_", with: "-").lowercased() == right.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(DesignTokens.Typography.body.weight(.medium))
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
