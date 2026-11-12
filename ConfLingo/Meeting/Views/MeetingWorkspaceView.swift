import SwiftUI

struct MeetingWorkspaceView: View {
    @Bindable var meeting: MeetingWorkspace
    @Binding var fontSize: Double
    let compact: () -> Void

    var sessions: SessionsLibrary?
    var library: KnowledgeLibrary?

    var body: some View {
        VStack(spacing: 0) {
            if meeting.page == .setup {
                preparation
            } else {
                header
                if let error = meeting.controller.lastError {
                    SessionErrorBanner(message: error).padding([.horizontal, .bottom], 16)
                }
                GeometryReader { geometry in
                    let layout = geometry.size.width >= 800
                        ? AnyLayout(HStackLayout(spacing: 16)) : AnyLayout(VStackLayout(spacing: 12))
                    layout {
                        insights
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        MeetingTranscriptView(meeting: meeting, fontSize: fontSize)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            Divider()
            MeetingTransport(meeting: meeting)
        }
        .disabled(meeting.isSavingSession || meeting.isUsingLibrary)
        .sheet(item: $meeting.selectedKnowledge) { reference in
            KnowledgeReferenceView(reference: reference, fontSize: fontSize)
        }
        .alert("現在の会議を破棄しますか？", isPresented: $meeting.showsDiscardConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("破棄して新しい会議へ", role: .destructive) { meeting.confirmDiscard() }
        } message: {
            Text("現在の会議の未保存の変更と資料全体を破棄します。保存済みセッション、資料ライブラリと書き出したMarkdownは残ります。")
        }
    }

    private var preparation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "会議を、はじめる。", subtitle: "自分と相手側の発話を、このMacで文字にします。", eyebrow: "Meeting / 準備")
                Surface {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField("会議名", text: $meeting.name)
                            .textFieldStyle(.roundedBorder).accessibilityLabel("会議名")
                        languagePicker("自分 · マイク", selection: $meeting.microphoneLocaleID)
                        languagePicker("相手側 · 内部音声", selection: $meeting.systemLocaleID)
                        Text("内部音声にはMacで再生する他の音も含まれます。ヘッドフォンの利用を推奨します。")
                            .font(.callout).foregroundStyle(DesignTokens.secondary)
                        Divider()
                        Toggle("参加者に文字起こしを通知し、同意を確認しました", isOn: $meeting.consentConfirmed)
                        Text("このチェックで参加者への通知が送信されることはありません。")
                            .font(.caption).foregroundStyle(DesignTokens.secondary)
                    }
                    .disabled(meeting.phase != .idle || meeting.isBusy)
                }
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("音声は保存・外部送信しません", systemImage: "checkmark.shield")
                            .font(.headline)
                        Text("発話はメモリ内に保持し、自動保存しません。終了後に「このMacに保存」を選べます。AI送信は下で明示的に許可した場合だけ行います。")
                            .font(.callout).foregroundStyle(DesignTokens.secondary)
                        ForEach([AudioOrigin.microphone, .systemAudio], id: \.self) { origin in
                            Text("\(origin.label)：\(permission(origin))").font(.caption)
                        }
                    }
                }
                MeetingAIControls(meeting: meeting)
                MeetingKnowledgeControls(meeting: meeting, library: library, fontSize: fontSize)
                if let error = meeting.controller.lastError { SessionErrorBanner(message: error) }
            }
            .padding(24)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(meeting.page == .review ? "Meeting / 振り返り" : "Meeting / General")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                Text(meeting.title).font(.title2.weight(.semibold)).lineLimit(2)
                Text(sessions?.status(for: meeting.sessionSnapshot) ?? "自動保存オフ · 終了後に保存またはMarkdown書き出し")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
            }
            Spacer(minLength: 8)
            Button("小さく表示", systemImage: "pip", action: compact)
        }
        .padding(20)
    }

    private var insights: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(meeting.page == .review ? "会議の振り返り" : "いま、役立つ提案")
                    .font(.headline).accessibilityAddTraits(.isHeader)
                if meeting.page == .live { MeetingAIControls(meeting: meeting) }
                if meeting.page == .review { MeetingReviewControls(meeting: meeting, fontSize: fontSize, sessions: sessions) }
                MeetingKnowledgeControls(meeting: meeting, library: library, fontSize: fontSize)
                if !meeting.candidates.items.isEmpty {
                    Text("決定・アクション候補").font(.headline)
                    Text("確認済みは利用者による確認を示します。参加者全員の合意や内容の正しさを保証するものではありません。")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    ForEach(meeting.candidates.items) { candidate in
                        MeetingInsightCard(meeting: meeting, insight: candidate.insight, fontSize: fontSize)
                    }
                }
                if meeting.insights.isEmpty {
                    Surface {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: "sparkles").font(.title2).foregroundStyle(DesignTokens.accent)
                            Text("会話の流れを確認できます")
                                .font(.title3.weight(.semibold))
                            Text("送信を許可するとAsk AIで質問できます。認識した発話は「会話の流れ」で確認できます。")
                                .foregroundStyle(DesignTokens.secondary)
                            if meeting.page == .review {
                                Text("確定した発話 \(meeting.store.finals.count)件。必要な文章は選択してコピーできます。")
                            }
                        }
                        .font(.callout)
                    }
                }
                ForEach(meeting.insights.reversed().filter { card in !meeting.candidates.items.contains { $0.id == card.id } }) { insight in
                    MeetingInsightCard(meeting: meeting, insight: insight, fontSize: fontSize)
                }
                Label(meeting.aiStatus, systemImage: "cloud")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if meeting.page == .review {
                    Text("「このMacに保存」で再起動後も振り返れます。Markdownの書き出しとは別の保存です。")
                        .font(.callout).foregroundStyle(DesignTokens.secondary)
                }
            }
            .padding(1)
        }
    }

    private func languagePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            Text("日本語").tag("ja-JP")
            Text("English").tag("en-US")
        }
    }

    private func permission(_ origin: AudioOrigin) -> String {
        switch meeting.controller.permissions[origin] {
        case .granted: "許可済み"
        case .denied: "未許可。システム設定のプライバシーとセキュリティをご確認ください"
        case .undetermined, .unknown, nil: "開始時にアクセスを確認します"
        }
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
                    StatusLabel(text: reviewLabel, symbol: "questionmark.circle", color: DesignTokens.warning)
                }
                .font(.caption)
                Text(insight.text).font(.system(size: fontSize, weight: .medium)).textSelection(.enabled)
                ForEach(insight.evidenceIDs, id: \.self) { id in
                    if let event = meeting.evidence(for: id) {
                        Text(event.text).font(.callout).foregroundStyle(DesignTokens.secondary).textSelection(.enabled)
                        Button("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)の発話を見る") {
                            meeting.revealEvidence(id)
                        }
                        .font(.caption)
                    } else {
                        Text("根拠の発話を参照できません").font(.caption).foregroundStyle(DesignTokens.warning)
                    }
                }
                ForEach(insight.knowledgeReferences) { reference in
                    Button("資料：\(reference.displayTitle) · \(reference.location)") {
                        if let revealKnowledge { revealKnowledge(reference) } else { meeting.selectedKnowledge = reference }
                    }.font(.caption)
                }
                if insight.hasInvalidEvidence {
                    Text("応答に確認できない根拠が含まれます・要確認").font(.caption).foregroundStyle(DesignTokens.warning)
                }
                if let candidate = meeting.candidates.items.first(where: { $0.id == insight.id }) {
                    ViewThatFits(in: .horizontal) {
                        HStack { reviewButtons(candidate) }
                        VStack(alignment: .leading) { reviewButtons(candidate) }
                    }
                    if !meeting.candidates.canConfirm(candidate.id) {
                        Text("有効な根拠が揃っていないため、確認済みにできません。")
                            .font(.caption).foregroundStyle(DesignTokens.warning)
                    }
                }
                if insight.evidenceIDs.isEmpty && insight.knowledgeReferences.isEmpty {
                    Text("根拠なし・要確認").font(.caption).foregroundStyle(DesignTokens.warning)
                }
            }
        }
    }
    private var reviewLabel: String {
        if let candidate = meeting.candidates.items.first(where: { $0.id == insight.id }) { return candidate.review.label }
        return insight.status == .generating ? "生成中・未検証" : insight.status == .interrupted ? "中断" : "要確認"
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
