import Foundation

enum MarkdownExporter {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// targetLanguage が nil の場合は文字起こしのみセッションとみなし、訳文ブロックを出力しない
    static func render(
        sessionName: String,
        date: Date,
        segments: [TranscriptSegment],
        sourceLanguage: String,
        targetLanguage: String?
    ) -> String {
        let name = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        lines.append("# ConfLingo Session: \(name.isEmpty ? "Untitled" : name)")
        lines.append("")
        lines.append("- Date: \(dateFormatter.string(from: date))")
        lines.append("- Source language: \(sourceLanguage)")
        if let targetLanguage {
            lines.append("- Target language: \(targetLanguage)")
        }
        lines.append("- Segments: \(segments.count)")
        lines.append("")
        lines.append("## Transcript")

        for segment in segments {
            lines.append("")
            if let startTime = segment.startTime {
                lines.append("### Segment \(segment.index) [\(timestamp(startTime))]")
            } else {
                lines.append("### Segment \(segment.index)")
            }
            lines.append("")
            lines.append("English:")
            lines.append(segment.english)
            if targetLanguage != nil {
                lines.append("")
                lines.append("Japanese:")
                lines.append(segment.japanese ?? "(untranslated)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// 録音開始からの経過秒を hh:mm:ss 形式にする
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
