import SwiftUI

struct MeetingTranscriptView: View {
    @Bindable var meeting: MeetingWorkspace
    let fontSize: Double
    @State private var followsLatest = true
    @State private var userScrolling = false
    @State private var atBottom = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        let events = meeting.transcriptEvents
        VStack(spacing: 0) {
            HStack {
                Text("会話の流れ").font(.headline)
                Spacer()
                Text(followsLatest ? "入力元ごとに表示" : "履歴を表示中")
                    .font(.caption).foregroundStyle(DesignTokens.secondary)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if events.isEmpty {
                            Text("発話が認識されると、ここに表示されます。")
                                .font(.callout).foregroundStyle(DesignTokens.secondary).padding(.vertical, 24)
                        }
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(event.origin.label)
                                    if !event.isFinal { Text("認識中") }
                                    Spacer()
                                    Text(MarkdownExporter.timestamp(event.startOffset)).monospacedDigit()
                                }
                                .font(.caption).foregroundStyle(DesignTokens.secondary)
                                Text(event.text).font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled)
                                if event.isFinal && meeting.page != .review {
                                    Button("この発話をWebで調べる") { meeting.research.open(event.text, evidenceIDs: [event.id]) }.font(.caption)
                                }
                                MeetingTranslationText(translations: meeting.translations, eventID: event.id, fontSize: fontSize,
                                                       sourceText: event.text, targetLanguage: meeting.translationTarget(for: event))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(meeting.selectedEvidence == event.id ? DesignTokens.accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .id(event.id)
                        }
                    }
                    .padding(12)
                }
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: [CGSize].self) { [$0.contentSize, $0.containerSize] } action: { _, _ in
                    if followsLatest { scrollPosition.scrollTo(edge: .bottom) }
                }
                .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 24 } action: { _, bottom in
                    atBottom = bottom
                    if userScrolling { followsLatest = bottom }
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating || phase == .tracking
                    if userScrolling { followsLatest = atBottom }
                }
                .onChange(of: meeting.store.displayRevision) {
                    if followsLatest { scrollPosition.scrollTo(edge: .bottom) }
                }
                .onChange(of: meeting.translations.displayRevision) {
                    if followsLatest { scrollPosition.scrollTo(edge: .bottom) }
                }
                .task(id: meeting.evidenceRequest) {
                    guard let id = meeting.selectedEvidence, meeting.evidence(for: id) != nil else { return }
                    followsLatest = false
                    // Let the outer scroll view reveal the pane before locating the utterance.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(id, anchor: .top)
                }
                .onChange(of: meeting.store.sessionID) { followsLatest = true }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button("最新へ", systemImage: "arrow.down") {
                            followsLatest = true
                            meeting.selectedEvidence = nil
                            scrollPosition.scrollTo(edge: .bottom)
                        }
                        .buttonStyle(.borderedProminent).padding(12)
                    }
                }
            }
            Divider()
            Text("入力元を表示しています。人物名の自動識別は行いません。")
                .font(.caption2).foregroundStyle(DesignTokens.secondary).padding(10)
        }
        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radius).stroke(DesignTokens.border))
    }
}
