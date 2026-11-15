import SwiftUI

struct SummarySectionContent: View {
    let meeting: MeetingWorkspace
    let section: MeetingSummarySection
    let fontSize: Double

    var body: some View {
        if !section.supplement.isEmpty { Text("会議の要約").font(DesignTokens.Typography.heading) }
        Text(section.text).font(.system(size: fontSize)).textSelection(.enabled)
        MeetingEvidenceLinks(meeting: meeting, ids: section.evidenceIDs)
        if !section.supplement.isEmpty {
            Text("資料・実装からの補足").font(DesignTokens.Typography.heading)
            Text(section.supplement).font(.system(size: fontSize)).textSelection(.enabled)
            ForEach(section.knowledgeReferences) { reference in
                Button("\(reference.displayTitle) · \(reference.location)") { meeting.selectedKnowledge = reference }.buttonStyle(AppButtonStyle(.link))
                    .font(DesignTokens.Typography.supporting)
            }
        }
    }
}

struct SummaryConfirmationView: View {
    @Bindable var meeting: MeetingWorkspace
    let dismiss: () -> Void
    @State private var plan: MeetingSummaryPlan
    @State private var includingKnowledge = false
    @State private var preparing = false
    @State private var error = ""
    @State private var prepareTask: Task<Void, Never>?
    @State private var submitted = false

    init(meeting: MeetingWorkspace, initialPlan: MeetingSummaryPlan, dismiss: @escaping () -> Void) {
        self.meeting = meeting
        self.dismiss = dismiss
        _plan = State(initialValue: initialPlan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("要約する内容を確認").font(DesignTokens.Typography.title)
            Text("この会議の確定発話\(plan.events.count)件を\(meeting.llmSettings.selected.name)へ送ります。会議中にAIを許可する前の発話も含まれます。音声は送りません。")
            Toggle("この要約では資料も参照する", isOn: $includingKnowledge)
                .disabled(meeting.knowledge.documents.isEmpty || meeting.knowledge.isBusy)
            Text("この要約だけの選択です。会議中の資料送信許可は変更しません。")
                .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.text)
            if preparing { ProgressView("区間ごとに資料を検索しています…") }
            if !error.isEmpty { InlineMessage(.failure, "要約の資料を準備できませんでした。確認画面を開き直してください。", details: error) }
            if !preparing && !meeting.isSummaryPlanCurrent(plan) {
                InlineMessage(.warning, "対象が変更されました。確認画面を開き直してください。")
            }
            Text("回答言語：\(plan.answerLanguage.label) · \(plan.requests.count)区間／最大\(plan.requests.count)要求。クラウドでは利用料金が発生する場合があります。自動再送はしません。")
            if plan.requests.count > 20 {
                Text("区間が多いため、処理に時間がかかります。区間ごとに順に送信し、利用料金も増える場合があります。開始後も「要約の送信を停止」で止められます。")
                    .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.warning)
            }
            if includingKnowledge {
                Text("資料名・相対パス・版・位置・抜粋も送ります。最大5箇所・6,000文字/区間。今回の資料本文：\(plan.requests.flatMap(\.knowledge).reduce(0) { $0 + $1.snippet.count })文字。")
                    .font(DesignTokens.Typography.body)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(plan.requests.enumerated()), id: \.element.id) { index, request in
                        Text("区間\(index + 1)").font(DesignTokens.Typography.heading)
                        if includingKnowledge && !preparing {
                            if request.knowledge.isEmpty { Text("一致資料なし。この区間は発話のみで要約します。").font(DesignTokens.Typography.supporting) }
                            ForEach(request.knowledge) { reference in
                                DisclosureGroup("\(reference.displayTitle) · \(reference.location) · \(reference.snippet.count)文字") {
                                    Text(reference.provenance).font(DesignTokens.Typography.supporting).textSelection(.enabled)
                                    Text(reference.snippet).textSelection(.enabled)
                                }
                            }
                        }
                        ForEach(request.events) { event in
                            Text("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)\n\(event.text)")
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("キャンセル") { prepareTask?.cancel(); meeting.cancelSummary(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("この内容を送って要約する") {
                    let approved = plan
                    submitted = true
                    dismiss()
                    Task { await meeting.generateSummary(approved, consent: true) }
                }
                .buttonStyle(AppButtonStyle(.primary))
                .disabled(preparing || !error.isEmpty || !meeting.isSummaryPlanCurrent(plan))
            }
        }
        .sheetSurface().frame(minWidth: 440, idealWidth: 620, minHeight: 400, idealHeight: 600)
        .onChange(of: includingKnowledge) { _, value in prepare(value) }
        .onDisappear {
            prepareTask?.cancel()
            if !submitted { meeting.cancelSummary() }
        }
    }

    private func prepare(_ include: Bool) {
        prepareTask?.cancel()
        meeting.cancelSummary()
        preparing = true
        error = ""
        prepareTask = Task {
            do {
                let next = try await meeting.summaryPlan(includingKnowledge: include)
                guard !Task.isCancelled else { return }
                plan = next
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error is CancellationError ? "資料が変更されました。確認画面を開き直してください。" : error.localizedDescription
            }
            preparing = false
        }
    }
}
