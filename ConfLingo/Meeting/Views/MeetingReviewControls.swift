import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingReviewControls: View {
    @Bindable var meeting: MeetingWorkspace
    let fontSize: Double
    @State private var pendingPlan: MeetingSummaryPlan?
    @State private var preparationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    Text("会話を振り返る").font(.headline)
                    Text("要約は任意です。AIを使わず、候補と発話だけを書き出すこともできます。")
                        .font(.callout).foregroundStyle(DesignTokens.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack { summaryButton; exportButton }
                        VStack(alignment: .leading) { summaryButton; exportButton }
                    }
                    if let preparationError { Text(preparationError).font(.callout).foregroundStyle(DesignTokens.warning) }
                    if meeting.summary.state == .sending {
                        ProgressView(value: Double(meeting.summary.draft.count), total: Double(max(1, meeting.summary.totalSections)))
                        Text("要約中：\(meeting.summary.draft.count) / \(meeting.summary.totalSections)区間完了 · Geminiへ送信中")
                            .font(.caption)
                        Button("要約の送信を停止", action: meeting.cancelSummary)
                        if !meeting.summary.partialText.isEmpty {
                            Text("生成中・未確認").font(.caption)
                            Text(meeting.summary.partialText).font(.system(size: fontSize)).textSelection(.enabled)
                        }
                    }
                    if case .failed(let error) = meeting.summary.state {
                        Text(error.localizedDescription).font(.callout).foregroundStyle(DesignTokens.warning)
                    }
                    if meeting.summary.state == .interrupted {
                        Text("要約を中断しました。後続の区間は送信しません。").font(.callout)
                    }
                    if meeting.summary.state != .complete, !meeting.summary.draft.isEmpty {
                        Text("今回の未完成要約：\(meeting.summary.draft.count)区間。Markdownには含めません。")
                            .font(.caption).foregroundStyle(DesignTokens.warning)
                    }
                    if meeting.summary.state != .complete {
                        ForEach(meeting.summary.draft) { section in
                            Text(section.text).font(.system(size: fontSize)).textSelection(.enabled)
                            MeetingEvidenceLinks(meeting: meeting, ids: section.evidenceIDs)
                        }
                    }
                    if !meeting.export.message.isEmpty {
                        Text(meeting.export.message).font(.caption)
                        if let snapshot = meeting.exportSnapshot, !meeting.export.matches(snapshot) {
                            Text("現在の内容は書き出し済みの内容と異なるか、まだ書き出されていません。")
                                .font(.caption).foregroundStyle(DesignTokens.warning)
                        }
                    }
                }
            }
            if let summary = meeting.summary.completed {
                Text("AIによる区間別要約 · 未確認").font(.headline)
                Text("各区間の内容は会議全体の最終合意ではありません。後の訂正と根拠を確認してください。")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
                if meeting.summary.state != .complete {
                    Text("前回の完成版を表示しています。").font(.caption)
                }
                ForEach(summary.sections) { section in
                    Surface {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(MarkdownExporter.timestamp(section.startOffset))–\(MarkdownExporter.timestamp(section.endOffset))")
                                .font(.caption)
                            Text(section.text).font(.system(size: fontSize)).textSelection(.enabled)
                            MeetingEvidenceLinks(meeting: meeting, ids: section.evidenceIDs)
                        }
                    }
                }
            }
        }
        .sheet(item: $pendingPlan) { plan in
                VStack(alignment: .leading, spacing: 16) {
                    Text("要約する内容を確認").font(.title2.bold())
                    Text("この会議の確定発話\(plan.events.count)件をGeminiへ送ります。会議中にAIを許可する前の発話も含まれます。音声は送りません。")
                    Text("回答言語：\(plan.answerLanguage.label) · \(plan.requests.count)区間／最大\(plan.requests.count)要求。利用料金が発生します。自動再送はしません。")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(plan.events) { event in
                                Text("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)\n\(event.text)")
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    HStack {
                        Button("キャンセル") { pendingPlan = nil; meeting.cancelSummary() }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("この内容を送って要約する") {
                            pendingPlan = nil
                            Task { await meeting.generateSummary(plan, consent: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24).frame(minWidth: 500, idealWidth: 620, minHeight: 400, idealHeight: 560)
        }
    }

    private var summaryButton: some View {
        Button(meeting.summary.completed == nil ? "AI要約を準備" : "AI要約を作り直す", systemImage: "sparkles") {
            do {
                pendingPlan = try meeting.summaryPlan()
                preparationError = nil
            } catch { preparationError = error.localizedDescription }
        }
        .disabled(meeting.summary.state == .sending || meeting.store.finals.isEmpty)
    }

    private var exportButton: some View {
        Button("Markdownを書き出す", systemImage: "square.and.arrow.up") {
            guard let snapshot = meeting.exportSnapshot else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = snapshot.filename
            guard panel.runModal() == .OK else { return }
            meeting.export.save(snapshot, to: panel.url)
        }
        .disabled(meeting.store.finals.isEmpty && meeting.candidates.items.isEmpty)
    }
}

struct MeetingEvidenceLinks: View {
    let meeting: MeetingWorkspace
    let ids: [UUID]

    var body: some View {
        ForEach(ids, id: \.self) { id in
            if let event = meeting.evidence(for: id) {
                Button("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)の発話を見る") {
                    meeting.revealEvidence(id)
                }
                .font(.caption)
            }
        }
    }
}
