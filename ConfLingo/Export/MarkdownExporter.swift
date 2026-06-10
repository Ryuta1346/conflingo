import Foundation

enum MarkdownExporter {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func render(sessionName: String, date: Date, segments: [TranscriptSegment]) -> String {
        let name = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        lines.append("# ConfLingo Session: \(name.isEmpty ? "Untitled" : name)")
        lines.append("")
        lines.append("- Date: \(dateFormatter.string(from: date))")
        lines.append("- Source language: en-US")
        lines.append("- Target language: ja-JP")
        lines.append("- Segments: \(segments.count)")
        lines.append("")
        lines.append("## Transcript")

        for segment in segments {
            lines.append("")
            lines.append("### Segment \(segment.index)")
            lines.append("")
            lines.append("English:")
            lines.append(segment.english)
            lines.append("")
            lines.append("Japanese:")
            lines.append(segment.japanese ?? "(untranslated)")
        }

        return lines.joined(separator: "\n")
    }
}
