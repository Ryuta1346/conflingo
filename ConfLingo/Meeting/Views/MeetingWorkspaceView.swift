import SwiftUI
import Translation

struct MeetingWorkspaceView: View {
    @Bindable var meeting: MeetingWorkspace
    @Binding var fontSize: Double
    let compact: () -> Void

    @State private var workspaceScrollPosition = ScrollPosition(edge: .top)

    var sessions: SessionsLibrary?
    var library: KnowledgeLibrary?
    var menuRequestsEnd: Binding<Bool> = .constant(false)

    var body: some View {
        VStack(spacing: 0) {
            if meeting.page == .setup {
                preparation
            } else {
                header
                if meeting.translations.pendingCount > 0 {
                    Text("翻訳待ち \(meeting.translations.pendingCount)件 · 保存には完成した訳文を含めます")
                        .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary).padding(.horizontal, 16)
                }
                if let failure = meeting.controller.failure {
                    InlineMessage(failure).padding([.horizontal, .bottom], 16)
                }
                GeometryReader { geometry in
                    let horizontal = geometry.size.width >= WorkspaceLayout.meetingColumnsWidth
                    let paneHeight = meeting.page == .live ? max(400, 160 + fontSize * 4) : 96 + max(160, fontSize * 4)
                    ScrollViewReader { proxy in
                        ScrollView {
                            MeetingPaneLayout(horizontal: horizontal, suggestionsFirst: meeting.page == .live) {
                                MeetingTranscriptView(meeting: meeting, fontSize: fontSize)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .id("meeting-transcript")
                                MeetingSupportView(meeting: meeting, library: library, fontSize: fontSize, scrollProxy: proxy) {
                                    insights
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilitySortPriority(!horizontal && meeting.page == .live ? 1 : 0)
                            }
                            .frame(height: max(geometry.size.height, horizontal ? paneHeight : paneHeight * 2 + 12))
                        }
                        .scrollPosition($workspaceScrollPosition)
                        .onChange(of: meeting.evidenceRequest) {
                            if meeting.page == .live {
                                proxy.scrollTo("meeting-transcript", anchor: .top)
                            } else {
                                workspaceScrollPosition.scrollTo(edge: .top)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            Divider()
            MeetingTransport(meeting: meeting, menuRequestsEnd: menuRequestsEnd)
        }
        .environment(\.readingFontSize, fontSize)
        .disabled(meeting.isSavingSession || meeting.isUsingLibrary)
        .sheet(item: $meeting.selectedKnowledge) { reference in
            KnowledgeReferenceView(reference: reference, fontSize: fontSize)
        }
        .alert("現在の会議を破棄しますか？", isPresented: $meeting.showsDiscardConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("破棄して新しい会議へ", role: .destructive) { meeting.confirmDiscard() }
        } message: {
            Text("現在の会議の未保存の変更と資料全体を破棄します。履歴に保存した記録、資料ライブラリと書き出したMarkdownは残ります。")
        }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "会議を、はじめる。", subtitle: "選んだ音声入力を、このMacで文字にします。", eyebrow: "Meeting / 準備")
                MeetingPreparationForm(meeting: meeting)
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("音声認識と翻訳は、このMacで", systemImage: "checkmark.shield")
                            .font(DesignTokens.Typography.heading)
                        Text("音声は保存・外部送信しません。翻訳モデルは初回にダウンロードが必要な場合があります。AIの回答言語と翻訳先は別設定です。自動保存はしません。準備中の完成したAI回答、または会議終了後の記録を「このMacに保存」で残せます。AI送信は下で明示的に許可した場合だけ行います。")
                            .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)

                    }
                }
                MeetingAIControls(meeting: meeting)
                ForEach(meeting.insights.reversed()) { insight in
                    MeetingInsightCard(meeting: meeting, insight: insight, fontSize: fontSize)
                }
                if !meeting.completedAssistance.isEmpty {
                    Surface { MeetingSaveControls(meeting: meeting, sessions: sessions) }
                }
                MeetingKnowledgeControls(meeting: meeting, library: library, fontSize: fontSize)
                if let failure = meeting.controller.failure { InlineMessage(failure) }
            }
            .padding(24)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.page == .review ? "Meeting / 振り返り" : "Meeting / ライブ")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                Text(meeting.title).font(DesignTokens.Typography.heading).lineLimit(2)
                Text(sessions?.status(for: meeting.sessionSnapshot) ?? "自動保存オフ · 終了後に保存またはMarkdown書き出し")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            }
            Spacer(minLength: 8)
            Button("小さく表示", systemImage: "pip", action: compact)
        }
        .padding(20)
    }

    private var insights: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(meeting.page == .review ? "会議の振り返り" : "いま、役立つ提案")
                .font(DesignTokens.Typography.heading).accessibilityAddTraits(.isHeader)
            if meeting.page == .review {
                MeetingReviewControls(meeting: meeting, fontSize: fontSize, sessions: sessions)
                ForEach(meeting.research.answers.reversed()) { answer in
                    AssistanceAnswerView(answer: answer, events: meeting.store.finals)
                }
            }
            MeetingKnowledgeControls(meeting: meeting, library: library, fontSize: fontSize)
            if !meeting.candidates.items.isEmpty {
                Text("決定・アクション候補").font(DesignTokens.Typography.heading)
                Text("確認済みは利用者による確認を示します。参加者全員の合意や内容の正しさを保証するものではありません。")
                    .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                ForEach(meeting.candidates.items) { candidate in
                    MeetingInsightCard(meeting: meeting, insight: candidate.insight, fontSize: fontSize)
                }
            }
            if meeting.insights.isEmpty && meeting.research.answers.isEmpty {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles").font(.title2).foregroundStyle(DesignTokens.accent)
                        Text("会話の流れを確認できます")
                            .font(DesignTokens.Typography.heading)
                        Text("送信を許可するとAsk AIで質問できます。認識した発話は「会話の流れ」で確認できます。")
                            .foregroundStyle(DesignTokens.text)
                        if meeting.page == .review {
                            Text("確定した発話 \(meeting.store.finals.count)件。必要な文章は選択してコピーできます。")
                        }
                    }
                    .font(DesignTokens.Typography.body)
                }
            }
            ForEach(meeting.insights.reversed().filter { card in !meeting.candidates.items.contains { $0.id == card.id } }) { insight in
                MeetingInsightCard(meeting: meeting, insight: insight, fontSize: fontSize)
            }
            Label(meeting.aiStatus, systemImage: "cloud")
                .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
            if meeting.page == .review {
                Text("「このMacに保存」で再起動後も振り返れます。Markdownの書き出しとは別の保存です。")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary)
            }
        }
        .padding(1)
    }

}

struct MeetingInsightCard: View {
    @Bindable var meeting: MeetingWorkspace
    let insight: MeetingInsight
    let fontSize: Double
    var revealKnowledge: ((KnowledgeReference) -> Void)?

    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(insight.kind.label, systemImage: "sparkles").foregroundStyle(DesignTokens.accent)
                    Spacer()
                    StatusLabel(text: badge.text, symbol: badge.symbol, color: badge.color)
                }
                .font(DesignTokens.Typography.supporting)
                Text(insight.text).font(.system(size: fontSize, weight: .medium)).textSelection(.enabled)
                ForEach(insight.evidenceIDs, id: \.self) { id in
                    if let event = meeting.evidence(for: id) {
                        Text(event.text).font(.system(size: fontSize)).foregroundStyle(DesignTokens.secondary).textSelection(.enabled)
                        Button("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)の発話を見る") {
                            meeting.revealEvidence(id)
                        }
                        .buttonStyle(AppButtonStyle(.link))
                    } else {
                        Text("根拠の発話を参照できません").font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.warning)
                    }
                }
                ForEach(insight.knowledgeReferences) { reference in
                    Button("資料：\(reference.displayTitle) · \(reference.location)") {
                        if let revealKnowledge { revealKnowledge(reference) } else { meeting.selectedKnowledge = reference }
                    }.font(DesignTokens.Typography.supporting).buttonStyle(AppButtonStyle(.link))
                }
                WebReferencesView(references: insight.webReferences ?? [])
                if meeting.page != .review {
                    Button("この提案をWebで調べる") { meeting.research.open(insight.text, evidenceIDs: insight.evidenceIDs) }
                }
                if insight.hasInvalidEvidence {
                    Text("応答に確認できない根拠が含まれます・要確認").font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.warning)
                }
                if let candidate = meeting.candidates.items.first(where: { $0.id == insight.id }) {
                    ViewThatFits(in: .horizontal) {
                        HStack { reviewButtons(candidate) }
                        VStack(alignment: .leading) { reviewButtons(candidate) }
                    }
                    if !meeting.candidates.canConfirm(candidate.id) {
                        Text("有効な根拠が揃っていないため、確認済みにできません。")
                            .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.warning)
                    }
                }
                if insight.evidenceIDs.isEmpty && insight.knowledgeReferences.isEmpty {
                    Text("根拠なし・要確認").font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.warning)
                }
            }
        }
    }
    private var badge: InsightReviewBadge {
        InsightReviewBadge(review: meeting.candidates.items.first { $0.id == insight.id }?.review, status: insight.status)
    }

    @ViewBuilder private func reviewButtons(_ candidate: MeetingCandidate) -> some View {
        if candidate.review != .confirmed {
            Button("確認済みにする") { meeting.candidates.setReview(.confirmed, for: candidate.id) }
                .disabled(!meeting.candidates.canConfirm(candidate.id))
                .accessibilityIdentifier("candidate-\(candidate.id)-confirm")
        }
        if candidate.review != .rejected {
            Button("却下する") { meeting.candidates.setReview(.rejected, for: candidate.id) }
                .accessibilityIdentifier("candidate-\(candidate.id)-reject")
        }
        if candidate.review != .unreviewed {
            Button("未確認に戻す") { meeting.candidates.setReview(.unreviewed, for: candidate.id) }
                .accessibilityIdentifier("candidate-\(candidate.id)-restore")
        }
    }

}
