import Foundation

@main struct Probe {
    @MainActor static func measure(_ name: String, count: Int, _ body: (Int) -> Int) {
        var checksum = 0
        for i in 0..<10 { checksum += body(i) }
        var samples: [Double] = []
        for trial in 0..<3 {
            let start = ContinuousClock.now
            for i in 0..<200 { checksum += body(i + trial * 200) }
            let elapsed = start.duration(to: .now).components
            samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        print("\(name),\(count),200,\(samples.sorted()[1]),\(checksum)")
    }
    @MainActor static func main() {
        print("case,finals,updates,median_total_ms,checksum")
        for count in [300, 3_000, 30_000] {
            let conference = SessionStore()
            for i in 0..<count {
                let id = conference.appendFinal("Synthetic sentence \(i).", startTime: Double(i))!
                let unit = conference.bufferSegment(id)!
                conference.applyTranslation(id: unit.id, japanese: "合成字幕 \(i)")
            }
            let pending = conference.appendFinal("Unfinished fragment")!
            _ = conference.bufferSegment(pending)
            for correctionsCount in [0, 20] {
                let corrections = conference.units.suffix(correctionsCount).map {
                    ConferenceCorrection(unitID: $0.id, sourceText: "Corrected", translation: "補正", adopted: true)
                }
                var previousSource: [TranscriptEntry] = []
                var previousTranslation: [TranscriptEntry] = []
                measure("conference-c\(correctionsCount)", count: count) { iteration in
                    conference.updateVolatile("Partial \(iteration)")
                    let source = TranscriptPresentation.source(conference, corrections: corrections)
                    let translated = TranscriptPresentation.translation(conference, corrections: corrections)
                    let sourceChanged = previousSource != source
                    let translationChanged = previousTranslation != translated
                    let changed = sourceChanged || translationChanged
                    previousSource = source
                    previousTranslation = translated
                    return source.count + translated.count + (changed ? 1 : 0)
                }
            }
            let meeting = MeetingSessionStore(sessionID: UUID())
            func event(id: UUID = UUID(), text: String, time: Double, final: Bool, revision: Int = 1) -> TranscriptEvent {
                TranscriptEvent(id: id, sessionID: meeting.sessionID, origin: .microphone, languageCode: "en-US",
                    startOffset: time, endOffset: time + 1, text: text, isFinal: final, revision: revision, sourceStartTime: time)
            }
            for i in 0..<count { meeting.receive(event(text: "Synthetic \(i)", time: Double(i), final: true)) }
            let partialID = UUID()
            var revision = 0
            var previous: [TranscriptEvent] = []
            measure("meeting-sort-and-compare", count: count) { iteration in
                revision += 1
                meeting.receive(event(id: partialID, text: "Partial \(iteration)", time: Double(count), final: false, revision: revision))
                // Exact current MeetingWorkspace.transcriptEvents expression.
                let events = (meeting.finals + meeting.partials).sorted { $0.startOffset < $1.startOffset }
                let changed = previous != events
                previous = events
                return events.count + (changed ? 1 : 0)
            }
        }
    }
}
