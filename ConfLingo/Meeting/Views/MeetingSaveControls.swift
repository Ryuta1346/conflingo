import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MeetingSaveControls: View {
    let meeting: MeetingWorkspace
    var sessions: SessionsLibrary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let sessions {
                SessionSaveControls(library: sessions, snapshot: meeting.sessionSnapshot) {
                    Task { await meeting.saveSession(to: sessions) }
                }
            }
            Button("Markdownを書き出す", systemImage: "square.and.arrow.up") {
                guard let snapshot = meeting.exportSnapshot else { return }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
                panel.nameFieldStringValue = snapshot.filename
                guard panel.runModal() == .OK else { return }
                meeting.export.save(snapshot, to: panel.url)
            }
            .disabled(meeting.exportSnapshot == nil || (meeting.store.finals.isEmpty
                && meeting.candidates.items.isEmpty && meeting.completedAssistance.isEmpty))
            if !meeting.export.message.isEmpty {
                Text(meeting.export.message).font(.caption)
                if let snapshot = meeting.exportSnapshot, !meeting.export.matches(snapshot) {
                    Text("現在の内容は書き出し済みの内容と異なるか、まだ書き出されていません。")
                        .font(.caption).foregroundStyle(DesignTokens.warning)
                }
            }
        }
    }
}
