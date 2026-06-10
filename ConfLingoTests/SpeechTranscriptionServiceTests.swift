import Speech
import Testing
@testable import ConfLingo

struct SpeechTranscriptionServiceTests {
    @Test func reportingOptionsDefaultPrioritizesAccuracy() {
        #expect(
            SpeechTranscriptionService.reportingOptions(fastResults: false)
                == [.volatileResults]
        )
    }

    @Test func reportingOptionsFastResultsPrioritizesLatency() {
        #expect(
            SpeechTranscriptionService.reportingOptions(fastResults: true)
                == [.volatileResults, .fastResults]
        )
    }
}
