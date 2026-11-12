import Foundation

struct ConferenceSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date?
    let sourceLanguage: String
    let targetLanguage: String?
    let segments: [TranscriptSegment]
    let units: [TranslationUnit]
    var support: ConferenceSupportSnapshot?
}

enum SessionSnapshot: Codable, Equatable, Sendable {
    case meeting(MeetingExportSnapshot, [MeetingInsight])
    case conference(ConferenceSnapshot)

    var id: UUID {
        switch self {
        case .meeting(let value, _): value.sessionID
        case .conference(let value): value.id
        }
    }

    var title: String {
        switch self {
        case .meeting(let value, _): value.title
        case .conference(let value): value.title
        }
    }

    var kind: String {
        switch self {
        case .meeting: "Meeting"
        case .conference: "Conference"
        }
    }

    var startedAt: Date? {
        switch self {
        case .meeting(let value, _): value.startedAt
        case .conference(let value): value.startedAt
        }
    }

    var markdown: String {
        switch self {
        case .meeting(let value, let cards):
            value.markdown + AssistanceMarkdown.render(cards.filter { card in
                !(value.assistance ?? []).contains { $0.id == card.id }
            }, speech: Dictionary(value.events.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first }))
        case .conference(let value):
            MarkdownExporter.render(sessionName: value.title, date: value.startedAt,
                                    segments: value.segments, units: value.units,
                                    sourceLanguage: value.sourceLanguage, targetLanguage: value.targetLanguage) + (value.support?.renderMarkdown(segments: value.segments) ?? "")
        }
    }

    var filename: String { "\(kind)-\(id.uuidString.prefix(8)).md" }

    func validate() throws {
        func require(_ valid: Bool) throws { if !valid { throw SessionFileError.invalid } }
        func time(_ value: Double) -> Bool { value.isFinite && value >= 0 && value < Double(Int.max) }
        func optionalTime(_ value: Double?) -> Bool { value.map(time) ?? true }
        func unique(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count }
        func references(_ values: [KnowledgeReference]) throws {
            for reference in values {
                try require(reference.startLine > 0 && reference.characterOffset >= 0 && !reference.snippet.isEmpty
                            && reference.startLine < Int.max - reference.snippet.count
                            && reference.characterOffset < Int.max)
                if let source = reference.source {
                    try require(!source.path.hasPrefix("/") && !source.path.split(separator: "/").contains(".."))
                }
            }
        }
        func webReferences(_ values: [WebReference]?) throws {
            let values = values ?? []
            try require(values.count <= 20 && unique(values.map(\.id)))
            for reference in values {
                try require(WebReference.validURL(reference.url) && reference.title.count <= 200
                            && reference.fetchedAt.timeIntervalSince1970.isFinite)
            }
        }
        try require(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try require(startedAt?.timeIntervalSince1970.isFinite ?? true)
        switch self {
        case .meeting(let value, let cards):
            let hasAnswers = (cards + (value.assistance ?? [])).contains { $0.status == .complete }
            try require((!value.events.isEmpty || hasAnswers) && unique(value.events.map(\.id)) && unique(cards.map(\.id))
                        && unique(value.candidates.map(\.id)))
            let ids = Set(value.events.map(\.id))
            for event in value.events {
                try require(event.sessionID == id && event.isFinal && time(event.startOffset)
                            && optionalTime(event.endOffset) && optionalTime(event.sourceStartTime)
                            && (event.endOffset.map { $0 >= event.startOffset } ?? true)
                            && !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            let translations = value.translations ?? []
            try require(unique(translations.map(\.id)))
            let events = Dictionary(uniqueKeysWithValues: value.events.map { ($0.id, $0) })
            for translation in translations {
                try require(events[translation.id]?.languageCode == translation.sourceLanguage
                            && !translation.sourceLanguage.isEmpty
                            && !translation.targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            && !translation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            for card in cards + (value.assistance ?? []) + value.candidates.map(\.insight) {
                try require(card.status == .complete && !card.text.isEmpty && card.evidenceIDs.allSatisfy { ids.contains($0) })
                try references(card.knowledgeReferences)
                try webReferences(card.webReferences)
                try require((card.searchSuggestionsHTML?.utf8.count ?? 0) <= 65_536)
            }
            for candidate in value.candidates {
                try require(candidate.sessionID == id && (candidate.insight.kind == .decisionCandidate || candidate.insight.kind == .actionCandidate))
                if candidate.review == .confirmed {
                    try require(!candidate.insight.hasInvalidEvidence && !candidate.evidenceIDs.isEmpty)
                }
            }
            if let summary = value.summary {
                try require(summary.sessionID == id && !summary.sections.isEmpty && unique(summary.sections.map(\.id)))
                for section in summary.sections {
                    try require(time(section.startOffset) && time(section.endOffset) && section.endOffset >= section.startOffset
                                && !section.evidenceIDs.isEmpty && section.evidenceIDs.allSatisfy { ids.contains($0) })
                    try references(section.knowledgeReferences)
                }
            }
        case .conference(let value):
            try require((!value.segments.isEmpty || value.support?.hasCompletedAnswers == true)
                        && unique(value.segments.map(\.id)) && unique(value.units.map(\.id)))
            let ids = Set(value.segments.map(\.id))
            for segment in value.segments { try require(optionalTime(segment.startTime) && optionalTime(segment.sessionOffset) && !segment.english.isEmpty) }
            for unit in value.units {
                try require(optionalTime(unit.startTime) && !unit.segmentIDs.isEmpty && unique(unit.segmentIDs)
                            && unit.segmentIDs.allSatisfy { ids.contains($0) })
            }
            if let support = value.support {
                try require(unique(support.answers.map(\.id)) && unique(support.corrections.map(\.id))
                            && Set(support.corrections.map(\.unitID)).count == support.corrections.count && support.terms.count <= 100)
                for answer in support.answers {
                    try require(answer.status == .complete && !answer.text.isEmpty && answer.text.count <= 8_000
                                && answer.evidenceIDs.allSatisfy { ids.contains($0) } && !answer.hasInvalidEvidence)
                    try references(answer.knowledgeReferences)
                    try webReferences(answer.webReferences)
                    try require((answer.searchSuggestionsHTML?.utf8.count ?? 0) <= 65_536)
                }
                for correction in support.corrections {
                    guard correction.adopted, let unit = value.units.first(where: { $0.id == correction.unitID }) else { throw SessionFileError.invalid }
                    try correction.validate(unit: unit)
                    try require(!correction.original.sourceLanguage.isEmpty && correction.original.targetLanguage?.isEmpty != true)
                    try references(correction.references)
                }
                for term in support.terms { try require(!term.term.isEmpty && term.term.count <= 80 && (term.target?.count ?? 0) <= 80 && term.line >= 0) }
            }
        }
    }
}

struct SavedSession: Codable, Equatable, Sendable, Identifiable {
    let version: Int
    let createdAt: Date
    let updatedAt: Date
    let snapshot: SessionSnapshot
    var id: UUID { snapshot.id }
}

struct SessionListEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let kind: String
    let startedAt: Date?
    let updatedAt: Date?
    let failure: String?
}
