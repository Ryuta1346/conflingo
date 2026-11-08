import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct MeetingOrderingTests {
    @Test func lateFinalsAreSortedAndEqualTimesKeepArrivalOrder() {
        let store = MeetingSessionStore(sessionID: UUID())
        for (text, time, origin) in [
            ("later", 8.0, AudioOrigin.microphone),
            ("first at two", 2.0, .systemAudio),
            ("second at two", 2.0, .microphone),
            ("earliest", 1.0, .systemAudio)
        ] {
            store.receive(TranscriptEvent(
                id: UUID(), sessionID: store.sessionID, origin: origin, languageCode: "en-US",
                startOffset: time, endOffset: time + 1, text: text, isFinal: true,
                revision: 1, sourceStartTime: time
            ))
        }
        #expect(store.finals.map(\.text) == ["earliest", "first at two", "second at two", "later"])
    }
}
