import Foundation
import Observation

struct DocumentTermCandidate: Identifiable, Equatable {
    let id = UUID()
    var term: String
    var target: String
    var selected = false
    let documentID: UUID?
    let documentTitle: String
    let line: Int
    let snippet: String
}

struct AppliedDocumentTerm: Codable, Equatable, Sendable {
    let term: String
    let target: String?
    let sourceLanguage: String
    let targetLanguage: String?
    let documentID: UUID?
    let documentTitle: String
    let line: Int
    let snippet: String
}

enum DocumentTermFailure: Error, LocalizedError {
    case conflict(String), limit, invalid
    var errorDescription: String? {
        switch self {
        case .conflict(let term): "「\(term)」の訳語が重複しています。使用する候補を1つ選んでください。"
        case .limit: "既存辞書と合わせて100語以内にしてください。"
        case .invalid: "用語・訳語は80文字以内の短い句にしてください。"
        }
    }
}

@MainActor
@Observable
final class DocumentTerms {
    var candidates: [DocumentTermCandidate] = []
    private(set) var applied: [AppliedDocumentTerm] = []
    private(set) var revision = UUID()

    func extract(_ documents: [KnowledgeArchive.Document]) {
        var result: [DocumentTermCandidate] = []
        var seen: Set<String> = []
        let marked = try? NSRegularExpression(pattern: #"\*\*([^*\n]+)\*\*|`([^`\n]+)`"#)
        for item in documents {
            var table: (Int, Int)?
            for (offset, raw) in item.body.components(separatedBy: "\n").enumerated() {
                guard result.count < 500 else { break }
                let line = raw.trimmingCharacters(in: .whitespaces)
                var values: [(String, String)] = []
                if line.hasPrefix("|") {
                    let cells = line.split(separator: "|", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }
                    let headers = cells.map { $0.lowercased() }
                    if let source = headers.firstIndex(where: { ["source", "term", "原語", "用語"].contains($0) }),
                       let target = headers.firstIndex(where: { ["target", "translation", "訳語"].contains($0) }) { table = (source, target) }
                    else if let (source, target) = table, cells.count > max(source, target), !cells.allSatisfy({ $0.allSatisfy { "-: ".contains($0) } }) {
                        values.append((cells[source], cells[target]))
                    }
                } else {
                    table = nil
                    if line.hasPrefix("#") { values.append((String(line.drop(while: { $0 == "#" || $0 == " " })), "")) }
                    let nsLine = line as NSString
                    for match in marked?.matches(in: line, range: NSRange(location: 0, length: nsLine.length)) ?? [] {
                        let range = match.range(at: match.range(at: 1).location != NSNotFound ? 1 : 2)
                        values.append((nsLine.substring(with: range), ""))
                    }
                }
                for (term, target) in values where Self.valid(term) && (target.isEmpty || Self.valid(target)) {
                    let key = term.lowercased() + "\u{1f}" + target
                    guard seen.insert(key).inserted, result.count < 500 else { continue }
                    result.append(.init(term: term, target: target, documentID: item.document.id,
                        documentTitle: item.document.displayTitle, line: offset + 1, snippet: String(line.prefix(240))))
                }
            }
        }
        candidates = result
    }

    func addManual(term: String, target: String) {
        candidates.append(.init(term: term, target: target, selected: true, documentID: nil,
                                documentTitle: "手入力", line: 0, snippet: ""))
    }

    func apply(sourceLanguage: String, targetLanguage: String?, manual: [KeywordParser.GlossaryEntry]) throws {
        var values: [AppliedDocumentTerm] = []
        var seen: [String: String] = [:]
        for candidate in candidates where candidate.selected {
            let term = candidate.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = candidate.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard Self.valid(term), target.isEmpty || Self.valid(target) else { throw DocumentTermFailure.invalid }
            let key = term.lowercased()
            if let previous = seen[key] {
                guard previous == target else { throw DocumentTermFailure.conflict(term) }
                continue
            }
            seen[key] = target
            values.append(.init(term: term, target: target.isEmpty ? nil : target,
                sourceLanguage: Self.language(sourceLanguage), targetLanguage: targetLanguage.map(Self.language),
                documentID: candidate.documentID, documentTitle: candidate.documentTitle, line: candidate.line, snippet: candidate.snippet))
        }
        guard Set(manual.map { $0.term.lowercased() }).union(values.map { $0.term.lowercased() }).count <= 100 else { throw DocumentTermFailure.limit }
        applied = values
        revision = UUID()
    }

    func glossary(sourceLanguage: String, targetLanguage: String?, manual: [KeywordParser.GlossaryEntry]) -> [KeywordParser.GlossaryEntry] {
        var result = manual
        var seen = Set(manual.map { $0.term.lowercased() })
        for term in applied where term.sourceLanguage == Self.language(sourceLanguage) {
            guard seen.insert(term.term.lowercased()).inserted else { continue }
            let target = term.targetLanguage == targetLanguage.map(Self.language) ? term.target : nil
            result.append(.init(term: term.term, target: target))
        }
        return Array(result.prefix(100))
    }

    func reset() { candidates = []; applied = []; revision = UUID() }

    private static func language(_ id: String) -> String { Locale(identifier: id).language.languageCode?.identifier ?? id }
    private static func valid(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && !value.contains(where: { $0.isNewline }) && value.split(separator: " ").count <= 8
    }
}
