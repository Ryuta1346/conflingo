import Foundation

@MainActor
enum LegacyTranscriptPresentation {
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

    static func translation(_ store: SessionStore, corrections: [ConferenceCorrection] = [],
                            preparation: TranslationCoordinator.PreparationState = .idle) -> [TranscriptEntry] {
        var entries = store.units.map { unit in
            if let correction = corrections.first(where: { $0.adopted && $0.unitID == unit.id }), let translation = correction.translation {
                return TranscriptEntry(id: unit.id.uuidString, text: translation + " （補正採用）", status: .final,
                                       time: unit.startTime, reservationText: unit.english)
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
                if case .failed = preparation {
                    text = "翻訳モデルを準備できませんでした。上の「翻訳を再試行」を操作してください。"
                    status = .failed
                } else {
                    text = preparation == .preparing ? "翻訳モデルを準備しています…" : "翻訳を待っています…"
                    status = .translating
                }
            }
            return TranscriptEntry(id: unit.id.uuidString, text: text, status: status, time: unit.startTime, reservationText: unit.english)
        }
        if !store.bufferedSegmentIDs.isEmpty || !store.volatileText.isEmpty {
            let buffered = Set(store.bufferedSegmentIDs)
            let source = (store.segments.filter { buffered.contains($0.id) }.map(\.english) + [store.volatileText])
                .filter { !$0.isEmpty }.joined(separator: " ")
            let bufferGeneration = store.units.last?.id ?? store.sessionID
            entries.append(TranscriptEntry(
                id: "buffered-\(bufferGeneration)", text: "発話が確定するのを待っています。", status: .translating, time: nil, reservationText: source
            ))
        }
        return entries
    }
}
