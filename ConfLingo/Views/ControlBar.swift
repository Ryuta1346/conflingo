import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 画面下部のコントロールバー。Start/Stop・保存・フォントサイズ・最前面表示・セッション名。
struct ControlBar: View {
    @Bindable var store: SessionStore
    let controller: SessionController
    let coordinator: TranslationCoordinator
    let speechLocale: Locale
    @Binding var fontSize: Double
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some View {
        HStack(spacing: 12) {
            TextField("セッション名", text: $store.sessionName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            startStopButton

            Button("Save Markdown") {
                saveMarkdown()
            }
            .disabled(store.segments.isEmpty)

            Button("Clear") {
                store.reset()
            }
            .disabled(store.phase != .idle || store.segments.isEmpty)

            Spacer()

            Toggle("最前面", isOn: $alwaysOnTop)
                .toggleStyle(.checkbox)

            Button("A−") {
                fontSize = max(10, fontSize - 2)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("A＋") {
                fontSize = min(48, fontSize + 2)
            }
            .keyboardShortcut("+", modifiers: .command)
        }
        .padding(12)
    }

    @ViewBuilder
    private var startStopButton: some View {
        switch store.phase {
        case .idle:
            Button("Start") {
                Task {
                    await controller.start(store: store, coordinator: coordinator, locale: speechLocale)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.borderedProminent)
        case .preparing:
            Button("Starting…") {}
                .disabled(true)
        case .listening:
            Button("Stop") {
                Task {
                    await controller.stop(store: store)
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        case .stopping:
            Button("Stopping…") {}
                .disabled(true)
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
            segments: store.segments
        )
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
