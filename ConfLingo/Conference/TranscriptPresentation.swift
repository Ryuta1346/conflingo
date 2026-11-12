import Foundation

struct TranscriptEntry: Identifiable, Equatable {
    enum Status: Equatable {
        case final, recognizing, translating, failed

        var label: String? {
            switch self {
            case .final: nil
            case .recognizing: "認識中"
            case .translating: "翻訳待ち"
            case .failed: "翻訳失敗"
            }
        }
    }

    let id: String
    let text: String
    let status: Status
    let time: TimeInterval?
}

@MainActor
enum TranscriptPresentation {
    static func source(_ store: SessionStore, corrections: [ConferenceCorrection] = []) -> [TranscriptEntry] {
        var replacements: [UUID: String] = [:]
        var omitted: Set<UUID> = []
        for correction in corrections where correction.adopted {
            guard let unit = store.units.first(where: { $0.id == correction.unitID }), let first = unit.segmentIDs.first else { continue }
            replacements[first] = correction.sourceText + " （補正採用）"
            omitted.formUnion(unit.segmentIDs.dropFirst())
        }
        var entries = store.segments.filter { !omitted.contains($0.id) }.map {
            TranscriptEntry(id: $0.id.uuidString, text: replacements[$0.id] ?? $0.english, status: .final, time: $0.startTime)
        }
        if !store.volatileText.isEmpty {
            entries.append(TranscriptEntry(id: "volatile", text: store.volatileText, status: .recognizing, time: nil))
        }
        return entries
    }

    static func translation(_ store: SessionStore, corrections: [ConferenceCorrection] = []) -> [TranscriptEntry] {
        var entries = store.units.map { unit in
            if let correction = corrections.first(where: { $0.adopted && $0.unitID == unit.id }), let translation = correction.translation {
                return TranscriptEntry(id: unit.id.uuidString, text: translation + " （補正採用）", status: .final, time: unit.startTime)
            }
            let text: String
            let status: TranscriptEntry.Status
            switch unit.translationState {
            case .done:
                text = unit.japanese ?? ""
                status = .final
            case .failed:
                text = "この部分を翻訳できませんでした。原文をご確認ください。"
                status = .failed
            case .pending, .translating:
                text = "翻訳を待っています…"
                status = .translating
            }
            return TranscriptEntry(id: unit.id.uuidString, text: text, status: status, time: unit.startTime)
        }
        if !store.bufferedSegmentIDs.isEmpty {
            entries.append(TranscriptEntry(
                id: "buffered", text: "発話が確定するのを待っています。", status: .translating, time: nil
            ))
        }
        return entries
    }
}
