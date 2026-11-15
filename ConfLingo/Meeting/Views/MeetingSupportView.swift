import SwiftUI

struct MeetingSupportView<ReviewContent: View>: View {
    @Bindable var meeting: MeetingWorkspace
    var library: KnowledgeLibrary?
    let fontSize: Double
    var scrollProxy: ScrollViewProxy?
    @ViewBuilder let reviewContent: ReviewContent
    @State private var showsSettings = false
    @State private var showsDocuments = false
    @FocusState private var settingsFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if meeting.page == .live {
                HStack {
                    Text("いま、役立つ提案").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button(meeting.ai.permitted ? "AI設定 · 許可済み" : "AI設定 · オフ") { showsSettings = true }
                        .focused($settingsFocused)
                    .id("meeting-ai-settings")
                    .onChange(of: settingsFocused) { _, focused in
                        if focused { scrollProxy?.scrollTo("meeting-ai-settings", anchor: .center) }
                    }
                }.padding(12)
                Divider()
            }
            ScrollView {
                if meeting.page == .live {
                    liveAnswers
                } else {
                    reviewContent.padding(1)
                }
            }
            if meeting.page == .live {
                Divider()
                MeetingQuestionComposer(meeting: meeting, openDocuments: { showsDocuments = true }, scrollProxy: scrollProxy).padding(12)
            }
        }
        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radius).stroke(DesignTokens.border))
        .sheet(isPresented: $showsSettings, onDismiss: { settingsFocused = true }) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("AI設定・送信範囲").font(.title2.bold())
                    Spacer()
                    Button("閉じる") { showsSettings = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView { MeetingAISettings(meeting: meeting).padding(1) }
            }.padding(24).frame(minWidth: 480, idealWidth: 600, minHeight: 480, idealHeight: 640)
        }
        .sheet(isPresented: $showsDocuments) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("会議の資料").font(.title2.bold())
                    Spacer()
                    Button("閉じる") { showsDocuments = false }.keyboardShortcut(.cancelAction)
                }
                ScrollView { MeetingKnowledgeControls(meeting: meeting, library: library, fontSize: fontSize) }
            }.padding(24).frame(minWidth: 480, idealWidth: 640, minHeight: 480, idealHeight: 640)
        }
    }

    private var liveAnswers: some View {
        VStack(alignment: .leading, spacing: 16) {
            if meeting.insights.isEmpty && meeting.research.answers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("提案はまだありません").font(.headline)
                    Text("会話は「会話の流れ」で確認できます。AIを使う場合は「AI設定」で送信範囲を確認してください。")
                        .font(.callout).foregroundStyle(DesignTokens.secondary)
                }.padding(8)
            }
            ForEach(meeting.insights.reversed().filter { card in !meeting.candidates.items.contains { $0.id == card.id } }) { insight in
                MeetingInsightCard(meeting: meeting, insight: insight, fontSize: fontSize)
            }
            ForEach(meeting.research.answers.reversed()) { answer in
                AssistanceAnswerView(answer: answer, events: meeting.store.finals,
                    research: { meeting.research.open($0, evidenceIDs: answer.evidenceIDs) })
            }
            if !meeting.candidates.items.isEmpty {
                Text("決定・アクション候補").font(.headline)
                Text("確認済みは利用者による確認を示します。参加者全員の合意や内容の正しさを保証するものではありません。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                ForEach(meeting.candidates.items) { candidate in
                    MeetingInsightCard(meeting: meeting, insight: candidate.insight, fontSize: fontSize)
                }
            }
        }.padding(12)
    }
}
