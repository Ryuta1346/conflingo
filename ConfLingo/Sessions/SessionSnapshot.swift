import Foundation

struct ConferenceSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date?
    let sourceLanguage: String
    let targetLanguage: String?
    let segments: [TranscriptSegment]
    let units: [TranslationUnit]
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
        case .meeting(let value, _): value.markdown
        case .conference(let value):
            MarkdownExporter.render(sessionName: value.title, date: value.startedAt,
                                    segments: value.segments, units: value.units,
                                    sourceLanguage: value.sourceLanguage, targetLanguage: value.targetLanguage)
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
        try require(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        try require(startedAt?.timeIntervalSince1970.isFinite ?? true)
        switch self {
        case .meeting(let value, let cards):
            try require(!value.events.isEmpty && unique(value.events.map(\.id)) && unique(cards.map(\.id))
                        && unique(value.candidates.map(\.id)))
            let ids = Set(value.events.map(\.id))
            for event in value.events {
                try require(event.sessionID == id && event.isFinal && time(event.startOffset)
                            && optionalTime(event.endOffset) && optionalTime(event.sourceStartTime)
                            && (event.endOffset.map { $0 >= event.startOffset } ?? true)
                            && !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            for card in cards + value.candidates.map(\.insight) {
                try require(card.status == .complete && !card.text.isEmpty && card.evidenceIDs.allSatisfy { ids.contains($0) })
                try references(card.knowledgeReferences)
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
            try require(!value.segments.isEmpty && unique(value.segments.map(\.id)) && unique(value.units.map(\.id)))
            let ids = Set(value.segments.map(\.id))
            for segment in value.segments { try require(optionalTime(segment.startTime) && !segment.english.isEmpty) }
            for unit in value.units {
                try require(optionalTime(unit.startTime) && !unit.segmentIDs.isEmpty && unique(unit.segmentIDs)
                            && unit.segmentIDs.allSatisfy { ids.contains($0) })
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
