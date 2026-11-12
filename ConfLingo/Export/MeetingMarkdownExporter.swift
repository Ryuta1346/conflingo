import Foundation
import Observation

struct MeetingExportSnapshot: Equatable, Codable, Sendable {
    let title: String
    let startedAt: Date?
    let microphoneLocale: String
    let systemLocale: String
    let sessionID: UUID
    let events: [TranscriptEvent]
    let candidates: [MeetingCandidate]
    let summary: MeetingSummary?
    var translations: [MeetingTranslation]? = nil

    var filename: String {
        let safe = title.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
        return "\(safe.isEmpty ? "Meeting" : String(safe.prefix(80)))-\(sessionID.uuidString.prefix(8)).md"
    }

    var markdown: String {
        let finals = events.filter { $0.sessionID == sessionID && $0.isFinal }.sorted { $0.startOffset < $1.startOffset }
        let eventsByID = Dictionary(finals.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines = ["# ConfLingo Meeting: \(Self.escape(title))", "",
                     "- 開始日時: \(startedAt.map { MarkdownExporter.dateFormatter.string(from: $0) } ?? "未取得")",
                     "- マイクの言語: \(Self.escape(microphoneLocale))", "- 内部音声の言語: \(Self.escape(systemLocale))",
                     "- 利用者の確認は、参加者全員の合意や内容の正しさを保証しません。", ""]
        if let summary, summary.sessionID == sessionID {
            lines += ["## AIによる区間別要約（未確認）", "", "回答言語: \(summary.answerLanguage.label)",
                      "各区間の記述は会議全体の最終合意を表しません。", ""]
            for section in summary.sections {
                lines += ["### \(Self.time(section.startOffset))–\(Self.time(section.endOffset))", ""]
                if !section.supplement.isEmpty { lines += ["#### 会議の要約", ""] }
                lines += [Self.quoted(section.text), "", references(section.evidenceIDs, eventsByID: eventsByID), ""]
                if !section.supplement.isEmpty {
                    lines += ["#### 資料・実装からの補足", "", Self.quoted(section.supplement), "",
                              knowledgeReferences(section.knowledgeReferences), ""]
                }
            }
        }
        for kind in [MeetingInsight.Kind.decisionCandidate, .actionCandidate] {
            lines += [kind == .decisionCandidate ? "## 確認済みの決定" : "## 確認済みのアクション", ""]
            lines += entries(candidates.filter { $0.review == .confirmed && $0.insight.kind == kind }, eventsByID: eventsByID)
        }
        for review in [MeetingCandidate.Review.unreviewed, .rejected] {
            lines += [review == .unreviewed ? "## 未確認の候補" : "## 却下した候補", ""]
            lines += entries(candidates.filter { $0.review == review }, eventsByID: eventsByID)
        }
        lines += ["## 確定発話", ""]
        let translated = Dictionary((translations ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for event in finals {
            lines += ["<a id=\"utterance-\(event.id.uuidString.lowercased())\"></a>",
                      "### \(Self.time(event.startOffset)) · \(event.origin.label)", "", Self.quoted(event.text), ""]
            if let translation = translated[event.id] {
                lines += ["訳文（\(Self.escape(translation.targetLanguage))）", "", Self.quoted(translation.text), ""]
            }
        }
        return lines.joined(separator: "\n")
    }

    private func entries(_ values: [MeetingCandidate], eventsByID: [UUID: TranscriptEvent]) -> [String] {
        let values = values.filter { $0.sessionID == sessionID }
        guard !values.isEmpty else { return ["なし", ""] }
        return values.flatMap { candidate in
            ["### \(candidate.insight.kind.label) · \(candidate.review.label)", "", Self.quoted(candidate.insight.text), "",
             references(candidate.evidenceIDs, eventsByID: eventsByID), knowledgeReferences(candidate.insight.knowledgeReferences), candidate.insight.hasInvalidEvidence ? "無効な根拠を含むため要確認。" : "", ""]
        }
    }

    private func knowledgeReferences(_ references: [KnowledgeReference]) -> String {
        references.map { reference in
            "資料: \(Self.escape(reference.displayTitle.components(separatedBy: .newlines).joined(separator: " "))) · \(Self.escape(reference.provenance.components(separatedBy: .newlines).joined(separator: " ")))\n取り込み日時: \(MarkdownExporter.dateFormatter.string(from: reference.importedAt))\n"
                + Self.quoted(reference.snippet)
        }.joined(separator: "\n\n")
    }

    private func references(_ ids: [UUID], eventsByID: [UUID: TranscriptEvent]) -> String {
        guard !ids.isEmpty else { return "根拠なし・要確認" }
        return "根拠: " + ids.map { id in
            guard let event = eventsByID[id] else { return "根拠を参照できません・要確認" }
            return "[\(Self.time(event.startOffset)) · \(event.origin.label)](#utterance-\(id.uuidString.lowercased()))"
        }.joined(separator: "、")
    }

    private static func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0, value < Double(Int.max) else { return "時刻不明" }
        return MarkdownExporter.timestamp(value)
    }

    private static func quoted(_ text: String) -> String {
        escape(text).components(separatedBy: .newlines).map { "> \($0)" }.joined(separator: "\n")
    }

    private static func escape(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        for character in ["\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!", "|"] {
            result = result.replacingOccurrences(of: character, with: "\\" + character)
        }
        return result
    }
}

@MainActor
@Observable
final class MeetingExportState {
    private(set) var message = ""
    private var lastSnapshot: MeetingExportSnapshot?

    func matches(_ snapshot: MeetingExportSnapshot) -> Bool { lastSnapshot == snapshot }

    func save(_ snapshot: MeetingExportSnapshot, to url: URL?,
              write: (String, URL) throws -> Void = { try $0.write(to: $1, atomically: true, encoding: .utf8) }) {
        guard let url else { return }
        let markdown = snapshot.markdown
        do {
            try write(markdown, url)
            lastSnapshot = snapshot
            message = "Markdownを書き出しました。アプリ内への永続保存ではありません。"
        } catch {
            message = "書き出しに失敗しました。保存先のアクセス権と空き容量を確認してください。会議内容は保持されています。"
        }
    }

    func reset() { lastSnapshot = nil; message = "" }
}
