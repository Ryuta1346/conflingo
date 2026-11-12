import Foundation

struct TranscriptCorrectionInput: Codable, Equatable, Sendable {
    let sourceText: String
    let translation: String?
    let sourceLanguage: String
    let targetLanguage: String?
    let terms: [AppliedDocumentTerm]
}

struct ConferenceCorrection: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let unitID: UUID
    let original: TranscriptCorrectionInput
    let sourceText: String
    let translation: String?
    let references: [KnowledgeReference]
    var adopted = false

    func validate(unit: TranslationUnit) throws {
        guard unit.id == unitID, unit.english == original.sourceText, !sourceText.isEmpty, sourceText.count <= 8_000,
              (translation?.count ?? 0) <= 8_000, !references.isEmpty,
              original.targetLanguage == nil || translation?.isEmpty == false,
              Self.numbers(original.sourceText) == Self.numbers(sourceText) else { throw InsightFailure.invalidResponse }
    }

    private static func numbers(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
    }
}

struct ConferenceSupportSnapshot: Codable, Equatable, Sendable {
    var answers: [MeetingInsight] = []
    var corrections: [ConferenceCorrection] = []
    var terms: [AppliedDocumentTerm] = []

    var markdown: String {
        var lines: [String] = []
        if !answers.isEmpty {
            lines += ["", "## 資料へのAI質問 · 要確認", ""]
            for answer in answers { lines += [quote(answer.text), citations(answer.knowledgeReferences), ""] }
        }
        if !corrections.isEmpty {
            lines += ["", "## 採用した資料参照補正", ""]
            for correction in corrections {
                lines += ["### 元の認識結果", quote(correction.original.sourceText), "### 採用した原文", quote(correction.sourceText)]
                if let translation = correction.original.translation { lines += ["### 元の訳文", quote(translation)] }
                if let translation = correction.translation { lines += ["### 採用した訳文", quote(translation)] }
                lines += [citations(correction.references), ""]
            }
        }
        if !terms.isEmpty {
            lines += ["", "## 適用した資料用語", ""]
            for term in terms { lines += [quote("\(term.term)\(term.target.map { " = " + $0 } ?? "") · \(term.sourceLanguage) → \(term.targetLanguage ?? "認識のみ") · \(term.documentTitle) · \(term.line)行"), quote(term.snippet)] }
        }
        return lines.joined(separator: "\n")
    }

    private func citations(_ references: [KnowledgeReference]) -> String {
        references.map { quote("資料: \($0.displayTitle) · \($0.provenance)") + "\n" + quote($0.snippet) }.joined(separator: "\n\n")
    }
    private func quote(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").components(separatedBy: .newlines).map { "> " + $0 }.joined(separator: "\n")
    }
}
