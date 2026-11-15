import SwiftUI

struct MeetingTranscriptView: View {
    @Bindable var meeting: MeetingWorkspace
    let fontSize: Double
    @State private var showsInputInfo = false
    @State private var followsLatest = true
    @State private var userScrolling = false
    @State private var atBottom = true
    @State private var scrollPosition = ScrollPosition(edge: .bottom)

    var body: some View {
        let events = meeting.transcriptEvents
        VStack(spacing: 0) {
            HStack {
                Text("会話の流れ").font(DesignTokens.Typography.heading)
                Spacer()
                if !followsLatest {
                    Text("履歴を表示中").font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                }
                Button("入力元の表示について", systemImage: "info.circle") { showsInputInfo = true }
                    .labelStyle(.iconOnly).buttonStyle(AppButtonStyle(.link))
                    .popover(isPresented: $showsInputInfo) {
                        VStack(alignment: .leading, spacing: 12) {
                            SheetHeader(title: "入力元の表示") { showsInputInfo = false }
                            Text("マイクと内部音声を記号と名前で区別します。人物名の自動識別は行いません。")
                                .font(DesignTokens.Typography.body)
                        }.sheetSurface().frame(width: 320)
                    }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if events.isEmpty {
                            Text("発話が認識されると、ここに表示されます。")
                                .font(DesignTokens.Typography.body).foregroundStyle(DesignTokens.secondary).padding(.vertical, 24)
                        }
                        ForEach(events) { event in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(event.origin.label, systemImage: event.origin == .microphone ? "mic" : "speaker.wave.2")
                                    if !event.isFinal { Text("認識中") }
                                    Spacer()
                                    Text(MarkdownExporter.timestamp(event.startOffset)).monospacedDigit()
                                    if event.isFinal && meeting.page != .review {
                                        Menu {
                                            MeetingUtteranceActions(meeting: meeting, event: event)
                                        } label: {
                                            Image(systemName: "ellipsis")
                                        }
                                        .menuStyle(.borderlessButton).fixedSize()
                                        .accessibilityLabel("\(MarkdownExporter.timestamp(event.startOffset))の発話の操作")
                                        .help("発話の操作")
                                    }
                                }
                                .font(DesignTokens.Typography.supporting).foregroundStyle(DesignTokens.secondary)
                                Text(event.text).font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled)
                                MeetingTranslationText(translations: meeting.translations, eventID: event.id, fontSize: fontSize,
                                                       sourceText: event.text, targetLanguage: meeting.translationTarget(for: event))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(meeting.selectedEvidence == event.id ? DesignTokens.accent.opacity(0.09) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contextMenu { MeetingUtteranceActions(meeting: meeting, event: event) }
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
                        .buttonStyle(AppButtonStyle(.primary)).padding(12)
                    }
                }
            }
        }
        .background(DesignTokens.surface, in: RoundedRectangle(cornerRadius: DesignTokens.radius))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.radius).stroke(DesignTokens.border))
    }
}

struct MeetingUtteranceActions: View {
    let meeting: MeetingWorkspace
    let event: TranscriptEvent

    var body: some View {
        if event.isFinal && meeting.page != .review {
            Button("この発話をWebで調べる", systemImage: "globe") {
                meeting.research.open(event.text, evidenceIDs: [event.id])
            }
        }
    }
}
