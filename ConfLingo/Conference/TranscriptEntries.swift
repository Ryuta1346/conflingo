import Foundation

final class TranscriptHistory {
    let entries: [TranscriptEntry]

    init(_ entries: [TranscriptEntry]) { self.entries = entries }
}

struct TranscriptEntries: RandomAccessCollection {
    struct Update: Equatable {
        let history: ObjectIdentifier
        let tail: TranscriptEntry?
    }

    let history: TranscriptHistory
    let tail: TranscriptEntry?

    var startIndex: Int { 0 }
    var endIndex: Int { history.entries.count + (tail == nil ? 0 : 1) }
    var update: Update { Update(history: ObjectIdentifier(history), tail: tail) }

    subscript(position: Int) -> TranscriptEntry {
        precondition(position >= startIndex && position < endIndex)
        if position < history.entries.count { return history.entries[position] }
        if let tail { return tail }
        preconditionFailure("Missing transcript entry")
    }
}
