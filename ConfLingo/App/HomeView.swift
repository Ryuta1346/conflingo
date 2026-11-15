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
                    subtitle: "会話を文字で追い、必要に応じて翻訳やAI支援を。",
                    eyebrow: "ConfLingo"
                )
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 24)], alignment: .leading, spacing: 24) {
                    conferenceCard
                    meetingCard
                }
                if hasTranscript {
                    Surface {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("現在の字幕").font(DesignTokens.Typography.heading)
                                Text("停止後にこのMacへ保存するか、Markdownを書き出せます。")
                                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary)
                            }
                            Spacer()
                            Button("字幕を開く", action: openTranscript)
                        }
                    }
                }
                if let sessions {
                    RecentSessionsView(library: sessions, showAll: showSessions, open: openSession)
                }
                Label("音声は保存せず、認識と翻訳はMacで処理します。", systemImage: "checkmark.shield")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary)
            }
            .padding(32)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
    private var conferenceCard: some View {
        HomeModeCard(title: "Conference", symbol: "captions.bubble",
                     description: "講演を文字で追い、必要に応じて翻訳。資料と発話から提案やWeb調査を利用できます。",
                     actionTitle: "字幕を準備する", action: prepare)
    }

    private var meetingCard: some View {
        HomeModeCard(title: "Meeting", symbol: "person.2",
                     description: "選んだ音声を文字起こし。資料と発話から提案やWeb調査を利用できます。",
                     actionTitle: "会議を開く", action: openMeeting)
    }
}

private struct HomeModeCard: View {
    let title: String
    let symbol: String
    let description: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Label(title, systemImage: symbol)
                    .font(DesignTokens.Typography.heading).foregroundStyle(DesignTokens.text)
                Text(description).font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.secondary).lineSpacing(5)
                    .frame(minHeight: 80, alignment: .topLeading)
                Button(actionTitle, systemImage: "arrow.right", action: action)
                    .buttonStyle(AppButtonStyle()).controlSize(.large)
            }
        }
    }
}
