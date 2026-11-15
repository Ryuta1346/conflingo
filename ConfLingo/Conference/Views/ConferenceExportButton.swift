import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConferenceExportButton: View {
    let store: SessionStore
    let sourceLanguage: String
    let targetLanguage: String?
    var support: ConferenceSupportSnapshot?
    @State private var notice: UserMessage?
    @State private var showsResult = false

    var body: some View {
        HStack(spacing: DesignTokens.Space.small) {
            Button("書き出す", systemImage: "square.and.arrow.up") { saveMarkdown() }
                .disabled(store.segments.isEmpty && support?.hasCompletedAnswers != true)
                .help("現在の字幕と完成した資料回答をMarkdownで書き出す")
            if let notice {
                Button { showsResult = true } label: {
                    Image(systemName: notice.kind.symbol).foregroundStyle(notice.kind.color)
                }
                .buttonStyle(AppButtonStyle(.link))
                .accessibilityLabel("書き出し結果：\(notice.text)")
                .popover(isPresented: $showsResult) {
                    VStack(alignment: .leading, spacing: DesignTokens.Space.large) {
                        SheetHeader(title: "書き出し結果") { showsResult = false }
                        InlineMessage(notice)
                    }.sheetSurface().frame(width: 420)
                }
            }
        }
    }

    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let baseName = store.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        panel.nameFieldStringValue = "\(baseName.isEmpty ? "ConfLingo" : baseName)-\(formatter.string(from: Date())).md"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let markdown = MarkdownExporter.render(
            sessionName: store.sessionName,
            date: store.startedAt ?? Date(),
            segments: store.segments,
            units: store.units,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) + (support?.renderMarkdown(segments: store.segments) ?? "")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            notice = UserMessage(.success, "Markdownを書き出しました。アプリ内への保存とは別に管理されます。")
        } catch {
            notice = UserMessage(.failure, "書き出しに失敗しました。保存先を確認してください。現在の字幕は保持しています。", details: error.localizedDescription)
            showsResult = true
        }
    }
}
