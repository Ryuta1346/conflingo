import Foundation

struct MeetingTranscriptTimeline<History: RandomAccessCollection>: RandomAccessCollection
where History.Element == TranscriptEvent, History.Index == Int {
    private let finals: History
    private let partials: [(position: Int, event: TranscriptEvent)]

    init(finals: History, partials: [TranscriptEvent]) {
        self.finals = finals
        self.partials = partials.sorted { $0.startOffset < $1.startOffset }.enumerated().map { offset, event in
            var lower = finals.startIndex
            var upper = finals.endIndex
            // Equal-time finals precede partials, matching the previous stable sort.
            while lower < upper {
                let middle = lower + (upper - lower) / 2
                if finals[middle].startOffset > event.startOffset { upper = middle }
                else { lower = middle + 1 }
            }
            return (lower - finals.startIndex + offset, event)
        }
    }

    var startIndex: Int { 0 }
    var endIndex: Int { finals.count + partials.count }
    subscript(position: Int) -> TranscriptEvent {
        precondition(position >= startIndex && position < endIndex)
        var preceding = 0
        for partial in partials {
            if partial.position == position { return partial.event }
            if partial.position > position { break }
            preceding += 1
        }
        return finals[finals.startIndex + position - preceding]
    }
}
