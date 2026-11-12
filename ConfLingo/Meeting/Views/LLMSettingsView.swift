import SwiftUI

struct LLMSettingsView: View {
    @Bindable var settings: LLMSettings
    @State private var editing: LLMConnection?
    @State private var confirmsDeletion = false
    @State private var confirmsKeyDeletion = false
    @State private var message = ""
    @State private var checking = false
    @State private var checkTask: Task<Void, Never>?
    @State private var checkID = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("使用するLLM").font(.headline)
            Picker("接続先", selection: Binding(get: { settings.selectedID }, set: { settings.select($0) })) {
                ForEach(settings.connections) { connection in
                    Text(connection.destinationLabel).tag(connection.id)
                }
            }
            Text(settings.selected.baseURL).font(.caption).textSelection(.enabled)
            Text(settings.credentials.statusText + (settings.selected.provider == .local ? "（ローカルではキーは任意）" : ""))
                .font(.caption)
            HStack {
                Menu("接続を追加") {
                    ForEach(LLMProvider.allCases) { provider in
                        Button(provider.label) { editing = .preset(provider) }
                    }
                }
                Button("編集・APIキー設定") { editing = settings.selected }
                Button("接続を削除", role: .destructive) { confirmsDeletion = true }
                    .disabled(settings.connections.count <= 1)
            }
            HStack {
                Button(checking ? "接続を確認中…" : "接続を確認") { checkConnection() }.disabled(checking)
                if checking { Button("中止") { cancelCheck() } }
                Button("APIキーを削除", role: .destructive) { confirmsKeyDeletion = true }
                    .disabled(!settings.credentials.configured)
            }
            Text("接続確認は架空の短文を1回送信します。クラウドではAPI料金が発生する場合があります。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            if !settings.credentials.message.isEmpty { Text(settings.credentials.message).font(.caption) }
            Text("接続先・モデル・キーの変更時はAI送信許可を解除します。キーはこのMacのKeychainに接続ごとに保存します。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            if settings.selected.provider == .local {
                Text("QwenなどのモデルをOllama / LM Studio等で起動してください。ローカル接続先の設定によっては、サーバー側からクラウドへ転送される場合があります。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
            }
        }
        .task(id: settings.selectedID) { await settings.credentials.refresh() }
        .onChange(of: settings.revision) { _, _ in cancelCheck(); message = "" }
        .onDisappear { cancelCheck() }
        .sheet(item: $editing) { connection in
            LLMConnectionEditor(settings: settings, connection: connection)
        }
        .alert("この接続とAPIキーを削除しますか？", isPresented: $confirmsDeletion) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                do { try settings.delete(settings.selectedID) }
                catch { message = InsightFailure.sanitized(error).localizedDescription }
            }
        }
        .alert("この接続のAPIキーを削除しますか？", isPresented: $confirmsKeyDeletion) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { settings.credentials.delete() }
        } message: { Text("このMacのキーを削除します。サービス側のキーは削除しません。") }
    }

    private func cancelCheck() {
        checkID = UUID()
        checkTask?.cancel()
        checkTask = nil
        checking = false
    }

    private func checkConnection() {
        cancelCheck()
        let operation = checkID
        checking = true
        message = ""
        let revision = settings.revision
        checkTask = Task {
            defer { if checkID == operation { checking = false } }
            do {
                let event = TranscriptEvent(id: UUID(), sessionID: UUID(), origin: .microphone, languageCode: "ja-JP",
                                            startOffset: 0, endOffset: 1, text: "これは接続確認用の架空の会話です。", isFinal: true, revision: 1, sourceStartTime: nil)
                let request = try InsightRequest(sessionID: event.sessionID, question: "接続確認とだけ答えてください。",
                                                 trigger: .manual, events: [event])
                let result = try await SelectedLLMClient(settings: settings).generate(request) { _ in }
                let card = try result.card(for: request)
                guard !card.hasInvalidEvidence else { throw InsightFailure.invalidResponse }
                guard !Task.isCancelled, checkID == operation, revision == settings.revision else { return }
                message = "接続と応答形式を確認しました。会議での回答品質はモデルによって異なります。"
            } catch {
                guard !Task.isCancelled, checkID == operation, revision == settings.revision else { return }
                message = InsightFailure.sanitized(error).localizedDescription
            }
        }
    }
}

private struct LLMConnectionEditor: View {
    @Environment(\.dismiss) private var dismiss
    let settings: LLMSettings
    @State private var draft: LLMConnection
    @State private var key = ""
    @State private var models: [LLMModel] = []
    @State private var message = ""
    @State private var loading = false
    @State private var modelTask: Task<Void, Never>?
    @State private var operation = UUID()

    init(settings: LLMSettings, connection: LLMConnection) {
        self.settings = settings
        _draft = State(initialValue: connection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(draft.provider.label)の接続設定").font(.title2.bold())
            Form {
                TextField("接続名", text: $draft.name)
                if draft.provider.isCustomEndpoint {
                    TextField("Base URL", text: $draft.baseURL)
                    if draft.provider == .local {
                        HStack {
                            Button("OllamaのURL") { draft.baseURL = "http://localhost:11434/v1" }
                            Button("LM StudioのURL") { draft.baseURL = "http://localhost:1234/v1" }
                        }
                        Text("PCに導入したQwen等を実行するソフトのAPIへ接続します。モデルのインストール・起動は実行ソフト側で行ってください。")
                            .font(.caption)
                    }
                } else { LabeledContent("接続先", value: draft.baseURL) }
                SecureField(draft.provider == .local ? "APIキー（任意）" : "APIキー", text: $key)
                Text("保存済みのキーを継続する場合は空欄にします。接続先URLを変更した場合はキーを再設定してください。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                TextField("モデルID", text: $draft.model)
                HStack {
                    Button(loading ? "取得中…" : "モデル一覧を取得") { loadModels() }.disabled(loading)
                    if loading { Button("中止") { cancelModels() } }
                    if !models.isEmpty {
                        Menu("取得したモデルから選ぶ") {
                            ForEach(models) { model in
                                Button(model.name == model.id ? model.id : "\(model.name) · \(model.id)") { draft.model = model.id }
                            }
                        }
                    }
                }
                Text("一覧の先頭ページを取得します。未掲載・一覧非対応の場合はモデルIDを直接入力できます。対応する応答形式は保存後の接続確認で検証してください。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if draft.provider.usesChatCompletions {
                    Picker("応答形式", selection: $draft.outputFormat) {
                        ForEach(LLMOutputFormat.allCases) { format in Text(format.label).tag(format) }
                    }
                    Text("サーバー・モデルが対応する形式を選びます。失敗時に自動で別の形式へ切り替えて再送しません。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                }
            }
            if !message.isEmpty { Text(message).font(.callout).foregroundStyle(DesignTokens.warning) }
            HStack {
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存して選択") { save() }.buttonStyle(.borderedProminent).disabled(loading)
            }
        }
        .padding(24).frame(width: 620)
        .onChange(of: draft.baseURL) { _, _ in cancelModels(); models = [] }
        .onChange(of: settings.revision) { _, _ in cancelModels(); models = [] }
        .onChange(of: key) { _, _ in cancelModels(); models = [] }
        .onDisappear { cancelModels(); key = "" }
    }

    private func cancelModels() { operation = UUID(); modelTask?.cancel(); modelTask = nil; loading = false }

    private func loadModels() {
        cancelModels()
        let token = operation
        let connection = draft
        let settingsRevision = settings.revision
        let enteredKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enteredKey.isEmpty || APIKeyCredentials.isValid(enteredKey) else { message = "有効なAPIキーを入力してください。"; return }
        loading = true
        message = ""
        modelTask = Task {
            defer { if operation == token { loading = false } }
            do {
                var value: String? = enteredKey.isEmpty ? nil : enteredKey
                if value == nil, let existing = settings.connections.first(where: { $0.id == connection.id }), existing.baseURL == connection.baseURL {
                    value = try await settings.credentials(for: existing).store.read()
                }
                try Task.checkCancellation()
                guard settings.revision == settingsRevision else { return }
                let result = try await LLMModelCatalog().models(for: connection, key: value)
                guard !Task.isCancelled, operation == token, settings.revision == settingsRevision else { return }
                models = result
                if result.isEmpty { message = "モデル候補を取得できませんでした。モデルIDを直接入力できます。" }
            } catch {
                guard !Task.isCancelled, operation == token, settings.revision == settingsRevision else { return }
                message = InsightFailure.sanitized(error).localizedDescription + " モデルIDの手入力も利用できます。"
            }
        }
    }

    private func save() {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.isEmpty || APIKeyCredentials.isValid(value) else { message = "有効なAPIキーを入力してください。"; return }
        do {
            draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
            draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            try settings.save(draft)
            if !value.isEmpty, !settings.credentials.save(value) { message = settings.credentials.message; return }
            key = ""
            dismiss()
        } catch { message = InsightFailure.sanitized(error).localizedDescription }
    }
}
