import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SavedSessionView: View {
    let saved: SavedSession
    let fontSize: Double
    let back: () -> Void
    let delete: () -> Void
    @State private var selectedReference: KnowledgeReference?
    @State private var exportMessage = ""

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Button("一覧へ", systemImage: "chevron.left", action: back)
                        Spacer()
                        Button("Markdownを書き出す", systemImage: "square.and.arrow.up", action: exportMarkdown)
                        Button("削除", systemImage: "trash", action: delete)
                    }
                    PageHeading(title: saved.snapshot.title, subtitle: "\(saved.snapshot.kind) · 保存した記録 / 読み取り専用", eyebrow: "Sessions")
                    Text("保存更新 \(saved.updatedAt.formatted(date: .abbreviated, time: .shortened)) · 開始 \(saved.snapshot.startedAt.map { MarkdownExporter.dateFormatter.string(from: $0) } ?? "未取得")")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    Text("保存時の内容です。音声取得・翻訳・AI送信は開始しません。")
                        .font(.callout).foregroundStyle(DesignTokens.secondary)
                    if !exportMessage.isEmpty { Text(exportMessage).font(.callout) }
                    switch saved.snapshot {
                    case .meeting(let snapshot, let cards):
                        meetingContent(snapshot, cards: cards, proxy: proxy)
                    case .conference(let snapshot):
                        conferenceContent(snapshot)
                    }
                }
                .padding(24).frame(maxWidth: 1000).frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $selectedReference) { reference in
            KnowledgeReferenceView(reference: reference, fontSize: fontSize)
        }
        .id(saved.id)
    }

    @ViewBuilder
    private func meetingContent(_ snapshot: MeetingExportSnapshot, cards: [MeetingInsight], proxy: ScrollViewProxy) -> some View {
        if let summary = snapshot.summary {
            Text("AIによる区間別要約 · 未確認").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("各区間の記述は会議全体の最終合意ではありません。回答言語：\(summary.answerLanguage.label)")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            ForEach(summary.sections) { section in
                Surface {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(MarkdownExporter.timestamp(section.startOffset))–\(MarkdownExporter.timestamp(section.endOffset))").font(.caption)
                        bodyText(section.text)
                        evidence(section.evidenceIDs, events: snapshot.events, proxy: proxy)
                        if !section.supplement.isEmpty {
                            Text("資料・実装からの補足").font(.headline)
                            bodyText(section.supplement)
                        }
                        references(section.knowledgeReferences)
                    }
                }
            }
        }
        if !snapshot.candidates.isEmpty {
            Text("決定・アクション候補").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            Text("確認済みは利用者による確認です。参加者全員の合意や正しさを保証しません。")
                .font(.caption).foregroundStyle(DesignTokens.secondary)
            ForEach(snapshot.candidates) { candidate in
                card(candidate.insight, review: candidate.review.label, events: snapshot.events, proxy: proxy)
            }
        }
        let otherCards = cards.filter { item in !snapshot.candidates.contains { $0.id == item.id } }
        if !otherCards.isEmpty {
            Text("AIの回答・提案 · 未確認").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ForEach(otherCards) { item in card(item, review: nil, events: snapshot.events, proxy: proxy) }
        }
        Text("確定発話").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        ForEach(snapshot.events) { event in
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label) · \(event.languageCode)")
                        .font(.caption).foregroundStyle(DesignTokens.secondary)
                    bodyText(event.text)
                }
            }
            .id(event.id)
        }
    }

    private func card(_ item: MeetingInsight, review: String?, events: [TranscriptEvent], proxy: ScrollViewProxy) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.kind.label + (review.map { " · " + $0 } ?? "")).font(.headline)
                bodyText(item.text)
                if item.hasInvalidEvidence { Text("無効な根拠を含むため要確認").foregroundStyle(DesignTokens.warning) }
                if item.evidenceIDs.isEmpty && item.knowledgeReferences.isEmpty {
                    Text("根拠なし・要確認").font(.caption)
                }
                evidence(item.evidenceIDs, events: events, proxy: proxy)
                references(item.knowledgeReferences)
            }
        }
    }

    @ViewBuilder
    private func evidence(_ ids: [UUID], events: [TranscriptEvent], proxy: ScrollViewProxy) -> some View {
        ForEach(Array(Set(ids)).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
            if let event = events.first(where: { $0.id == id }) {
                Button("\(MarkdownExporter.timestamp(event.startOffset)) · \(event.origin.label)の発話を見る") { proxy.scrollTo(id, anchor: .top) }
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func references(_ values: [KnowledgeReference]) -> some View {
        ForEach(Array(values.enumerated()), id: \.offset) { _, reference in
            Button { selectedReference = reference } label: {
                Label("\(reference.displayTitle) · \(reference.startLine)–\(reference.endLine)行", systemImage: "doc.text")
                    .font(.caption).multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private func conferenceContent(_ snapshot: ConferenceSnapshot) -> some View {
        if let support = snapshot.support {
            ConferenceSavedSupportView(support: support, fontSize: fontSize)
        }
        Text("原文 · \(snapshot.sourceLanguage)").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
        ForEach(snapshot.segments) { segment in
            Surface {
                VStack(alignment: .leading, spacing: 10) {
                    Text(segment.startTime.map(MarkdownExporter.timestamp) ?? "時刻不明").font(.caption)
                    bodyText(segment.english)
                }
            }
        }
        if let language = snapshot.targetLanguage {
            Text("翻訳 · \(language)").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            ForEach(snapshot.units) { unit in
                Surface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(unit.startTime.map(MarkdownExporter.timestamp) ?? "時刻不明").font(.caption)
                        bodyText(unit.english)
                        if let translation = unit.japanese { bodyText(translation) }
                        else {
                            Text(translationStatus(unit.translationState)).foregroundStyle(DesignTokens.secondary).font(.callout)
                        }
                    }
                }
            }
        }
    }

    private func translationStatus(_ state: TranslationState) -> String {
        switch state {
        case .failed: "保存時点で翻訳失敗"
        case .pending, .translating: "保存時点で未完了・未翻訳"
        case .done: "訳文なし"
        }
    }

    private func bodyText(_ text: String) -> some View { Text(text).font(.system(size: fontSize)).textSelection(.enabled) }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = saved.snapshot.filename
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try saved.snapshot.markdown.write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "Markdownを書き出しました。アプリ内の保存とは別に管理されます。"
        } catch { exportMessage = "書き出しに失敗しました。保存したセッションは保持されています。" }
    }
}
