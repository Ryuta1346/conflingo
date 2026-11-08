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
    static func source(_ store: SessionStore) -> [TranscriptEntry] {
        var entries = store.segments.map {
            TranscriptEntry(id: $0.id.uuidString, text: $0.english, status: .final, time: $0.startTime)
        }
        if !store.volatileText.isEmpty {
            entries.append(TranscriptEntry(id: "volatile", text: store.volatileText, status: .recognizing, time: nil))
        }
        return entries
    }

    static func translation(_ store: SessionStore) -> [TranscriptEntry] {
        var entries = store.units.map { unit in
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
