import Foundation

enum MarkdownExporter {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// targetLanguage が nil の場合は文字起こしのみセッションとみなし、認識セグメント単位で出力する。
    /// 翻訳セッションでは翻訳単位（複数セグメントを文末まで結合したもの）で出力する。
    static func render(
        sessionName: String,
        date: Date,
        segments: [TranscriptSegment],
        units: [TranslationUnit] = [],
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
        lines.append("- Segments: \(targetLanguage == nil ? segments.count : units.count)")
        lines.append("")
        lines.append("## Transcript")

        if targetLanguage == nil {
            for segment in segments {
                lines.append(contentsOf: entry(
                    index: segment.index, startTime: segment.startTime,
                    english: segment.english, japanese: nil
                ))
            }
        } else {
            for unit in units {
                lines.append(contentsOf: entry(
                    index: unit.index, startTime: unit.startTime,
                    english: unit.english, japanese: unit.japanese ?? "(untranslated)"
                ))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func entry(
        index: Int,
        startTime: TimeInterval?,
        english: String,
        japanese: String?
    ) -> [String] {
        var lines = ["", heading(index: index, startTime: startTime), "", "English:", english]
        if let japanese {
            lines.append(contentsOf: ["", "Japanese:", japanese])
        }
        return lines
    }

    private static func heading(index: Int, startTime: TimeInterval?) -> String {
        if let startTime {
            "### Segment \(index) [\(timestamp(startTime))]"
        } else {
            "### Segment \(index)"
        }
    }

    /// 録音開始からの経過秒を hh:mm:ss 形式にする
    static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
