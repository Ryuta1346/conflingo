import Foundation

enum AssistanceMarkdown {
    static func render(_ answers: [MeetingInsight], speech: [UUID: String] = [:]) -> String {
        guard !answers.isEmpty else { return "" }
        var lines = ["", "## AIの回答・提案・Web調査 · 要確認", ""]
        for answer in answers where answer.status == .complete {
            var text = quote(answer.text)
            for (index, reference) in (answer.webReferences ?? []).enumerated() where WebReference.validURL(reference.url) {
                text = text.replacingOccurrences(of: "[[web:\(reference.id)]]", with: "[\(index + 1)](<\(reference.url.absoluteString)>)")
            }
            lines += [text]
            for id in answer.evidenceIDs {
                lines += ["発話の根拠:", quote(speech[id] ?? "参照できません・要確認")]
            }
            for reference in answer.knowledgeReferences {
                lines += [quote("資料：\(reference.displayTitle) · \(reference.provenance)"), quote(reference.snippet)]
            }
            for reference in answer.webReferences ?? [] where WebReference.validURL(reference.url) {
                lines += [quote("Web：\(reference.title) · 取得 \(reference.fetchedAt.ISO8601Format())"),
                          "<\(reference.url.absoluteString)>", "Webの生抜粋は保存していません。"]
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func quote(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
    }
}
