import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConferenceExportButton: View {
    let store: SessionStore
    let sourceLanguage: String
    let targetLanguage: String?
    var support: ConferenceSupportSnapshot?

    var body: some View {
        Button("書き出す", systemImage: "square.and.arrow.up") { saveMarkdown() }
            .disabled(store.segments.isEmpty)
            .help("現在の字幕をMarkdownで書き出す")
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
        ) + (support?.markdown ?? "")
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert()
            alert.messageText = "保存に失敗しました"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
