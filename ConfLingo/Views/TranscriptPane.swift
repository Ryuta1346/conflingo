import SwiftUI

struct TranscriptPane: View {
    let title: String
    let entries: [TranscriptEntry]
    let fontSize: Double
    @State private var followsLatest = true
    @State private var userScrolling = false
    @State private var atBottom = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                Spacer()
                if !followsLatest {
                    Text("履歴を表示中").font(.caption).foregroundStyle(DesignTokens.secondary)
                }
            }
            .padding(12)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if entries.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "waveform").font(.title2)
                                Text("字幕を待っています").font(.headline)
                                Text("音声が認識されると、ここに表示されます。").font(.callout)
                            }
                            .foregroundStyle(DesignTokens.secondary)
                            .padding(.vertical, 24)
                        }
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if let time = entry.time {
                                        Text(MarkdownExporter.timestamp(time)).monospacedDigit()
                                    }
                                    if let status = entry.status.label { Text(status) }
                                }
                                .font(.caption)
                                .foregroundStyle(entry.status == .failed ? DesignTokens.danger : DesignTokens.secondary)
                                Text(entry.text)
                                    .font(.system(size: fontSize))
                                    .lineSpacing(6)
                                    .foregroundStyle(entry.status == .final ? DesignTokens.text : DesignTokens.secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(16)
                }
                .clipped()
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 24
                } action: { _, bottom in
                    atBottom = bottom
                    if userScrolling { followsLatest = bottom }
                }
                .onScrollPhaseChange { _, phase in
                    userScrolling = phase == .interacting || phase == .decelerating || phase == .tracking
                    if userScrolling { followsLatest = atBottom }
                }
                .onChange(of: entries) {
                    if followsLatest { proxy.scrollTo("latest", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest {
                        Button("最新へ", systemImage: "arrow.down") {
                            followsLatest = true
                            proxy.scrollTo("latest", anchor: .bottom)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(14)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignTokens.surface)
    }
}
