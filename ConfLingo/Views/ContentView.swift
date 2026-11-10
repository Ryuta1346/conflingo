import AppKit
import SwiftUI
import Translation

struct ContentView: View {
    @State private var meeting: MeetingWorkspace
    @State private var floatingPanel: MeetingFloatingPanel
    @Environment(\.openWindow) private var openWindow
    @State private var store: SessionStore
    @State private var coordinator = TranslationCoordinator()
    @State private var availability = ModelAvailabilityService()
    @State private var controller: SessionController
    @State private var navigation: ConferenceNavigation
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var profileStore: KeywordProfileStore
    @State private var showDictionary = false
    @State private var showClearConfirmation = false
    @State private var preparationRetry = 0
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var closeRequested = false
    @State private var showCloseBlocked = false
    @AppStorage("fontSize") private var fontSize = 16.0
    @AppStorage("sourceLocaleID") private var sourceLocaleID = "en-US"
    @AppStorage("targetLanguageID") private var targetLanguageID = "ja"
    @AppStorage("transcriptionOnly") private var transcriptionOnly = false
    @AppStorage("fastFinalization") private var fastFinalization = false
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false
    @AppStorage("appearance") private var appearance = "system"
    private let isPreview: Bool

    init(activity: AudioInputUse = AudioInputUse(), preview: Bool = false, defaults: UserDefaults = .standard,
         meeting: MeetingWorkspace? = nil, floatingPanel: MeetingFloatingPanel? = nil, meetingPreview: Bool = false) {
        #if DEBUG
        isPreview = preview
        #else
        isPreview = false
        #endif
        let session = SessionStore()
        let settings: UserDefaults
        #if DEBUG
        settings = isPreview ? (meetingPreview ? MeetingPreview.defaults : ConferencePreview.defaults) : defaults
        if isPreview { ConferencePreview.populate(session) }
        #else
        settings = defaults
        #endif
        _fontSize = AppStorage(wrappedValue: 16, "fontSize", store: settings)
        _sourceLocaleID = AppStorage(wrappedValue: "en-US", "sourceLocaleID", store: settings)
        _targetLanguageID = AppStorage(wrappedValue: "ja", "targetLanguageID", store: settings)
        _transcriptionOnly = AppStorage(wrappedValue: false, "transcriptionOnly", store: settings)
        _fastFinalization = AppStorage(wrappedValue: false, "fastFinalization", store: settings)
        _alwaysOnTop = AppStorage(wrappedValue: false, "alwaysOnTop", store: settings)
        _appearance = AppStorage(wrappedValue: "system", "appearance", store: settings)
        #if DEBUG
        _meeting = State(initialValue: meeting ?? (isPreview ? MeetingPreview.make(activity: activity, defaults: settings)
            : MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting), defaults: settings)))
        #else
        _meeting = State(initialValue: meeting ?? MeetingWorkspace(controller: DualTranscriptionController(activity: activity, owner: .meeting), defaults: settings))
        #endif
        _floatingPanel = State(initialValue: floatingPanel ?? MeetingFloatingPanel(defaults: settings))
        _store = State(initialValue: session)
        _controller = State(initialValue: SessionController(activity: activity))
        _navigation = State(initialValue: ConferenceNavigation(destination: meetingPreview ? .meeting : isPreview ? .live : .home))
        _profileStore = State(initialValue: KeywordProfileStore(defaults: settings))
    }

    var body: some View {
        AppShellView(destination: navigation.destination, phase: activePhase, navigate: navigate) {
            VStack(spacing: 0) {
                topBar
                Divider()
                if let error = controller.lastError {
                    SessionErrorBanner(message: error).padding([.horizontal, .top], 16)
                }
                ZStack {
                    page
                    MeetingWorkspaceView(meeting: meeting, fontSize: $fontSize,
                                         compact: { meeting.cancelSummary(); floatingPanel.show(meeting: meeting, compactMain: true) })
                        .opacity(navigation.destination == .meeting ? 1 : 0)
                        .allowsHitTesting(navigation.destination == .meeting)
                        .disabled(navigation.destination != .meeting)
                        .accessibilityHidden(navigation.destination != .meeting)
                }
                if navigation.destination == .setup || navigation.destination == .live {
                    Divider()
                    ControlBar(phase: store.phase, isStopping: controller.isStopping,
                               canStart: modelState == .ready, hasTranscript: !store.segments.isEmpty,
                               start: startSession, stop: { Task { await stopSession() } })
                }
            }
        }
        .onAppear {
            floatingPanel.expand = {
                openWindow(id: "main")
                return navigation.requestMeetingExpansion(conferencePhase: store.phase)
            }
        }
        .onChange(of: navigation.destination) { _, destination in
            if destination != .meeting { meeting.cancelSummary() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            meeting.cancelSummary()
        }
        .background(WindowCloseGuard(shouldClose: shouldCloseWindow))
        .background(MeetingWindowAttachment(floating: floatingPanel))
        .alert("処理が完了するまでお待ちください", isPresented: $showCloseBlocked) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("開始・停止の処理中です。停止が失敗した場合は「停止を再試行」を操作してください。")
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(isPresented: $showDictionary) {
            KeywordProfileEditor(profiles: profileStore).disabled(store.phase != .idle)
        }
        .alert(closeRequested ? "音声収集を停止してウィンドウを閉じますか？" : "音声収集を停止して移動しますか？", isPresented: $navigation.showsStopConfirmation) {
            Button("キャンセル", role: .cancel) { navigation.cancelNavigation(); closeRequested = false }
            Button(closeRequested ? "停止して閉じる" : "停止して移動") {
                Task {
                    await navigation.confirmNavigation(phase: { activePhase }, stop: stopActiveSession)
                    if closeRequested && activePhase == .idle { dismissWindow(id: "main") }
                    closeRequested = false
                }
            }
        } message: {
            Text(closeRequested ? "停止が完了した後にウィンドウを閉じます。アプリを終了すると未保存の内容は失われます。" : "ここまでの字幕は保持します。停止が完了すると画面を切り替えます。")
        }
        .alert("字幕を消去しますか？", isPresented: $showClearConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("消去", role: .destructive) { controller.reset(store: store) }
        } message: {
            Text("現在の字幕を消去します。書き出し済みのMarkdownは削除しません。")
        }
        .task(id: "\(sourceLocaleID)->\(targetLanguageID)|only=\(transcriptionOnly)|retry=\(preparationRetry)") {
            guard !isPreview else { return }
            // 起動時・言語ペア変更時・文字起こしのみモード切替時に利用可能性を再チェックする
            translationConfiguration = nil
            let ready = await availability.checkAndPrepare(
                sourceLocaleID: sourceLocaleID,
                targetLanguageID: transcriptionOnly ? nil : targetLanguageID
            )
            guard ready, !Task.isCancelled else { return }
            if transcriptionOnly {
                // 消費されないキューにバッファが溜まらないよう finish し、以降の enqueue を no-op にする
                coordinator.finish()
            } else {
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
            guard !isPreview else { return }
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

    @ViewBuilder
    private var page: some View {
        switch navigation.destination {
        case .home:
            HomeView(hasTranscript: !store.segments.isEmpty,
                     prepare: { navigate(.setup) }, openTranscript: { navigate(.live) },
                     openMeeting: { navigate(.meeting) })
        case .setup:
            ConferenceSetupView(
                sessionName: $store.sessionName, sourceLanguage: $sourceLocaleID,
                targetLanguage: $targetLanguageID, transcriptionOnly: $transcriptionOnly,
                fastFinalization: $fastFinalization, profiles: profileStore,
                sourceLocales: sourceLocales, targetLanguages: targetLanguages,
                modelState: modelState, downloadProgress: availability.downloadProgress,
                canEdit: store.phase == .idle, hasTranscript: !store.segments.isEmpty,
                editDictionary: { showDictionary = true }, retry: { preparationRetry += 1 },
                openTranscript: { navigate(.live) }
            )
        case .live:
            ConferenceLiveView(
                store: store, sourceLanguage: sourceLocaleID,
                targetLanguage: transcriptionOnly ? nil : targetLanguageID,
                profileName: profileStore.selectedProfile.name, fontSize: $fontSize,
                editSettings: { navigate(.setup) },
                clear: { showClearConfirmation = true }
            )
        case .meeting:
            Color.clear
        case .settings:
            SettingsView(fontSize: $fontSize, alwaysOnTop: $alwaysOnTop, appearance: $appearance,
                         answerLanguage: Binding(get: { meeting.answerLanguage }, set: { meeting.answerLanguage = $0 }),
                         credentials: meeting.credentials,
                         editDictionary: { showDictionary = true }, prepare: { navigate(.setup) })
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(navigation.destination == .home ? "ConfLingo" : navigation.destination == .settings ? "設定" : navigation.destination == .meeting ? "Meeting" : "Conference")
                .font(.callout.weight(.medium))
                .foregroundStyle(DesignTokens.secondary)
            Spacer(minLength: 8)
            if navigation.destination == .live || navigation.destination == .meeting {
                Button("A−") { fontSize = max(10, fontSize - 2) }
                    .keyboardShortcut("-", modifiers: .command)
                    .accessibilityLabel("字幕を小さく")
                Button("A＋") { fontSize = min(48, fontSize + 2) }
                    .keyboardShortcut("+", modifiers: .command)
                    .accessibilityLabel("字幕を大きく")
                Toggle(isOn: $alwaysOnTop) { Label("最前面", systemImage: "pin") }
                    .toggleStyle(.button)
                if navigation.destination == .live {
                    ConferenceExportButton(store: store, sourceLanguage: sourceLocaleID,
                                           targetLanguage: transcriptionOnly ? nil : targetLanguageID)
                }
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(DesignTokens.surface)
    }

    private var modelState: ModelAvailabilityService.State { isPreview ? .ready : availability.state }

    private var sourceLocales: [Locale] {
        if isPreview { return [Locale(identifier: "en-US"), Locale(identifier: "ja-JP"), Locale(identifier: "de-DE")] }
        let locales = availability.supportedSourceLocales
        return locales.contains { $0.identifier == sourceLocaleID } ? locales : [Locale(identifier: sourceLocaleID)] + locales
    }

    private var targetLanguages: [Locale.Language] {
        if isPreview { return [.init(identifier: "ja"), .init(identifier: "en"), .init(identifier: "de")] }
        let languages = availability.supportedTargetLanguages
        return languages.contains { $0.minimalIdentifier == targetLanguageID } ? languages : [.init(identifier: targetLanguageID)] + languages
    }

    private var activePhase: SessionPhase { meeting.phase != .idle ? meeting.phase : store.phase }

    private func stopActiveSession() async {
        if meeting.phase != .idle { await meeting.pause() } else { await stopSession() }
    }

    private func shouldCloseWindow(_: NSWindow) -> Bool {
        switch activePhase {
        case .idle:
            meeting.cancelSummary()
            return true
        case .listening:
            closeRequested = true
            navigation.request(navigation.destination, phase: activePhase, forceConfirmation: true)
        case .preparing, .stopping:
            showCloseBlocked = true
        }
        return false
    }

    private func navigate(_ destination: ConferenceNavigation.Destination) {
        if destination != .meeting { meeting.cancelSummary() }
        navigation.request(destination, phase: activePhase)
    }

    private func startSession() {
        guard modelState == .ready, store.phase == .idle else { return }
        navigate(.live)
        if isPreview {
            store.phase = .listening
            store.updateVolatile("And that gives us a different way to think about…")
            return
        }
        Task {
            await controller.start(
                store: store, coordinator: coordinator,
                locale: availability.speechLocale ?? Locale(identifier: sourceLocaleID),
                glossary: KeywordParser.parseGlossary(profileStore.selectedProfile.keywords),
                fastResults: transcriptionOnly && fastFinalization
            )
        }
    }

    private func stopSession() async {
        if isPreview {
            store.phase = .idle
            store.updateVolatile("")
            return
        }
        await controller.stop(store: store, coordinator: coordinator)
    }
}

#Preview {
    ContentView(preview: true)
        .frame(width: 1280, height: 800)
}
