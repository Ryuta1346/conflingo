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
    var reservationText: String?
}

@MainActor
enum TranscriptPresentation {
    struct SourceKey: Equatable {
        let session: UUID
        let segments: Int
        let units: Int
        let corrections: [ConferenceCorrection]
    }

    struct TranslationKey: Equatable {
        let session: UUID
        let revision: Int
        let corrections: [ConferenceCorrection]
        let preparation: TranslationCoordinator.PreparationState
    }

    final class Cache {
        var sourceKey: SourceKey?
        var source: TranscriptHistory?
        var translationKey: TranslationKey?
        var translation: TranscriptHistory?
    }

    static func source(_ store: SessionStore, corrections: [ConferenceCorrection] = []) -> TranscriptEntries {
        let key = SourceKey(session: store.sessionID, segments: store.segments.count,
                            units: corrections.isEmpty ? 0 : store.units.count, corrections: corrections)
        let cache = store.transcriptCache
        let history: TranscriptHistory
        if cache.sourceKey == key, let cached = cache.source {
            history = cached
        } else {
            history = TranscriptHistory(sourceHistory(store, corrections: corrections))
            cache.source = history
            cache.sourceKey = key
        }
        let tail = store.volatileText.isEmpty ? nil : TranscriptEntry(id: "volatile", text: store.volatileText, status: .recognizing, time: nil)
        return TranscriptEntries(history: history, tail: tail)
    }

    private static func sourceHistory(_ store: SessionStore, corrections: [ConferenceCorrection]) -> [TranscriptEntry] {
        var replacements: [UUID: String] = [:]
        var omitted: Set<UUID> = []
        for correction in corrections where correction.adopted {
            guard let unit = store.units.first(where: { $0.id == correction.unitID }), let first = unit.segmentIDs.first else { continue }
            replacements[first] = correction.sourceText + " （補正採用）"
            omitted.formUnion(unit.segmentIDs.dropFirst())
        }
        return store.segments.filter { !omitted.contains($0.id) }.map {
            TranscriptEntry(id: $0.id.uuidString, text: replacements[$0.id] ?? $0.english, status: .final, time: $0.startTime)
        }
    }

    static func translation(_ store: SessionStore, corrections: [ConferenceCorrection] = [],
                            preparation: TranslationCoordinator.PreparationState = .idle) -> TranscriptEntries {
        let key = TranslationKey(session: store.sessionID, revision: store.translationRevision,
                                 corrections: corrections, preparation: preparation)
        let cache = store.transcriptCache
        let history: TranscriptHistory
        if cache.translationKey == key, let cached = cache.translation {
            history = cached
        } else {
            history = TranscriptHistory(translationHistory(store, corrections: corrections, preparation: preparation))
            cache.translation = history
            cache.translationKey = key
        }
        var tail: TranscriptEntry?
        if !store.bufferedSegmentIDs.isEmpty || !store.volatileText.isEmpty {
            let source = [store.bufferedSourceText, store.volatileText]
                .filter { !$0.isEmpty }.joined(separator: " ")
            let bufferGeneration = store.units.last?.id ?? store.sessionID
            tail = TranscriptEntry(
                id: "buffered-\(bufferGeneration)", text: "発話が確定するのを待っています。", status: .translating, time: nil, reservationText: source
            )
        }
        return TranscriptEntries(history: history, tail: tail)
    }

    private static func translationHistory(_ store: SessionStore, corrections: [ConferenceCorrection],
                                           preparation: TranslationCoordinator.PreparationState) -> [TranscriptEntry] {
        store.units.map { unit in
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
    }
}
