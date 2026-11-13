import Foundation
import Testing
@testable import ConfLingo

struct MeetingTranscriptTimelineTests {
    @Test(arguments: [0, 1, 5, 30_000])
    func suffixReadsOnlyBinarySearchPathsAndVisibleRows(count: Int) {
        let session = UUID()
        let finals = (0..<count).map { insightEvent(session: session, offset: Double($0 * 2)) }
        let partials = [insightEvent(session: session, offset: 1, final: false),
                        insightEvent(session: session, offset: Double(count * 2), final: false)]
        let reads = ReadCount()
        let history = CountingEvents(events: finals, reads: reads)
        let timeline = MeetingTranscriptTimeline(finals: history, partials: partials)
        let last = Array(timeline.suffix(3))
        #expect(last == Array((finals + partials).sorted { $0.startOffset < $1.startOffset }.suffix(3)))
        #expect(reads.value <= 40, "Two binary searches and at most three visible history rows")
    }

    @Test func emptySingleAndTwoPartialsMatchStableChronologicalOrder() {
        let session = UUID()
        let finals = [0.0, 10, 10, 20].map { insightEvent(session: session, offset: $0) }
        for times in [[], [-1], [5], [10], [30], [10, 10], [15, -1], [0, 30]] as [[Double]] {
            let partials = times.map { insightEvent(session: session, offset: $0, final: false) }
            let expected = (finals + partials).sorted { $0.startOffset < $1.startOffset }
            let timeline = MeetingTranscriptTimeline(finals: finals, partials: partials)
            #expect(Array(timeline) == expected)
            #expect(Array(timeline.reversed()) == expected.reversed())
            #expect(Array(timeline.dropFirst().prefix(2)) == Array(expected.dropFirst().prefix(2)))
        }
    }

    @Test func nonZeroHistoryIndicesRemainValid() {
        let events = (0..<10).map { insightEvent(offset: Double($0)) }
        let history = events[3..<8]
        let partials = [insightEvent(offset: 4, final: false)]
        let timeline = MeetingTranscriptTimeline(finals: history, partials: partials)
        #expect(Array(timeline) == (Array(history) + partials).sorted { $0.startOffset < $1.startOffset })
    }
}

private final class ReadCount {
    var value = 0
}

private struct CountingEvents: RandomAccessCollection {
    let events: [TranscriptEvent]
    let reads: ReadCount
    var startIndex: Int { events.startIndex }
    var endIndex: Int { events.endIndex }
    subscript(position: Int) -> TranscriptEvent {
        reads.value += 1
        return events[position]
    }
}
