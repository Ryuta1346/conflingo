import SwiftUI
import Translation

struct ContentView: View {
    @State private var store = SessionStore()
    @State private var coordinator = TranslationCoordinator()
    @State private var availability = ModelAvailabilityService()
    @State private var controller = SessionController()
    @State private var translationConfiguration: TranslationSession.Configuration?
    @AppStorage("fontSize") private var fontSize = 16.0

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
        .task {
            await availability.checkAndPrepare()
            if availability.state == .ready {
                translationConfiguration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ja")
                )
            }
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
                    let response = try await session.translate(item.text)
                    await store.applyTranslation(id: item.id, japanese: response.targetText)
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
                TranscriptPane(title: "English transcript", entries: englishEntries, fontSize: fontSize)
                TranscriptPane(title: "日本語翻訳", entries: japaneseEntries, fontSize: fontSize)
            }

            Divider()

            ControlBar(
                store: store,
                controller: controller,
                coordinator: coordinator,
                speechLocale: availability.speechLocale ?? Locale(identifier: "en_US"),
                fontSize: $fontSize
            )
        }
    }

    private var englishEntries: [TranscriptPane.Entry] {
        var entries = store.segments.map {
            TranscriptPane.Entry(id: $0.id.uuidString, text: $0.english, dimmed: false)
        }
        if !store.volatileText.isEmpty {
            entries.append(TranscriptPane.Entry(id: "volatile", text: store.volatileText, dimmed: true))
        }
        return entries
    }

    private var japaneseEntries: [TranscriptPane.Entry] {
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
