import SwiftUI

struct HomeView: View {
    let hasTranscript: Bool
    let prepare: () -> Void
    let openTranscript: () -> Void
    var openMeeting: () -> Void = {}

    var sessions: SessionsLibrary?
    var showSessions: () -> Void = {}
    var openSession: (UUID) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeading(
                    title: "会話に、集中できる場所。",
                    subtitle: "聞きながら、原文と翻訳を読む。",
                    eyebrow: "ConfLingo"
                )
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 28))
                            .foregroundStyle(DesignTokens.accent)
                        Text("Conference").font(.title2.weight(.semibold))
                        Text("講演やセッションの理解を支えます。\n言語と専門用語を選んで、字幕をはじめましょう。")
                            .foregroundStyle(DesignTokens.secondary)
                            .lineSpacing(5)
                        Button("字幕を準備する", systemImage: "arrow.right", action: prepare)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                if hasTranscript {
                    Surface {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("現在の字幕").font(.headline)
                                Text("停止後にこのMacへ保存するか、Markdownを書き出せます。")
                                    .font(.callout).foregroundStyle(DesignTokens.secondary)
                            }
                            Spacer()
                            Button("字幕を開く", action: openTranscript)
                        }
                    }
                }
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Meeting", systemImage: "person.2").font(.title2.weight(.semibold))
                        Text("自分と相手側の発話を、このMacで文字起こし。会議の流れを読み返せます。")
                            .foregroundStyle(DesignTokens.secondary)
                        Button("会議を開く", systemImage: "arrow.right", action: openMeeting)
                            .buttonStyle(.bordered).controlSize(.large)
                    }
                }
                if let sessions {
                    RecentSessionsView(library: sessions, showAll: showSessions, open: openSession)
                }
                Label("音声は保存せず、認識と翻訳はMacで処理します。", systemImage: "checkmark.shield")
                    .font(.callout).foregroundStyle(DesignTokens.secondary)
            }
            .padding(32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}
