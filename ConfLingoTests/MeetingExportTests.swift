import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct MeetingExportTests {
    @Test func changedReviewSummaryAndMetadataAreNotMarkedAsExported() throws {
        let store = summaryStore(count: 1)
        let event = try #require(store.finals.first)
        let candidate = MeetingCandidate(sessionID: store.sessionID, insight: MeetingInsight(
            kind: .decisionCandidate, text: "Synthetic decision", priority: 1, evidenceIDs: [event.id]))
        func snapshot(title: String = "Test", candidates: [MeetingCandidate], summary: MeetingSummary? = nil) -> MeetingExportSnapshot {
            MeetingExportSnapshot(title: title, startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                  sessionID: store.sessionID, events: store.finals, candidates: candidates, summary: summary)
        }
        let original = snapshot(candidates: [candidate])
        let exporter = MeetingExportState()
        let url = URL(fileURLWithPath: "/private/tmp/conflingo-pr7-export-test.md")
        exporter.save(original, to: url) { _, _ in }
        var confirmed = candidate
        confirmed.review = .confirmed
        let changed = snapshot(candidates: [confirmed])
        #expect(!exporter.matches(changed))
        #expect(exporter.matches(snapshot(candidates: [candidate])))
        #expect(!exporter.matches(snapshot(title: "Renamed", candidates: [candidate])))
        let summary = MeetingSummary(sessionID: store.sessionID, answerLanguage: .english, sections: [
            MeetingSummarySection(id: UUID(), text: "Synthetic summary", evidenceIDs: [event.id], startOffset: 0, endOffset: 1)
        ])
        #expect(!exporter.matches(snapshot(candidates: [candidate], summary: summary)))
        exporter.save(changed, to: nil) { _, _ in Issue.record("Cancelled export wrote a file") }
        exporter.save(changed, to: url) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(exporter.matches(original))
        #expect(!exporter.matches(changed))
        exporter.save(changed, to: url) { _, _ in }
        #expect(exporter.matches(changed))
        #expect(!exporter.matches(original))
    }

    @Test func longMeetingPreservesAllReferencesAndDetectsUnchangedExport() {
        let store = summaryStore(count: 3_000)
        let candidates = (0..<120).map { index in
            MeetingCandidate(sessionID: store.sessionID, insight: MeetingInsight(
                kind: .decisionCandidate, text: "Synthetic decision", priority: 1,
                evidenceIDs: Array(store.finals[(index * 20)..<(index * 20 + 30)]).map(\.id)))
        }
        let snapshot = MeetingExportSnapshot(title: "Benchmark", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                              sessionID: store.sessionID, events: store.finals, candidates: candidates, summary: nil)
        let exporter = MeetingExportState()
        let start = ContinuousClock.now
        exporter.save(snapshot, to: URL(fileURLWithPath: "/private/tmp/conflingo-export-benchmark.md")) { markdown, _ in
            #expect(markdown.components(separatedBy: "<a id=").count - 1 == 3_000)
            #expect(markdown.components(separatedBy: "](#utterance-").count - 1 == 3_600)
            #expect(markdown.contains("Synthetic line 2999"))
        }
        let rendered = ContinuousClock.now
        #expect(exporter.matches(snapshot))
        print("Meeting export benchmark: render=\(start.duration(to: rendered)), match=\(rendered.duration(to: .now))")
    }

    @Test func exportSeparatesReviewStatesAndEscapesUntrustedText() throws {
        let store = summaryStore(count: 1)
        let event = try #require(store.finals.first)
        let candidateStore = MeetingCandidateStore(transcript: store)
        for (index, review) in MeetingCandidate.Review.allCases.enumerated() {
            let card = MeetingInsight(kind: index == 1 ? .decisionCandidate : .actionCandidate,
                                      text: "Item \(index)\n# Confirmed <script> [x](https://invalid)", priority: 1, evidenceIDs: [event.id])
            candidateStore.receive(card, sessionID: store.sessionID)
            candidateStore.setReview(review, for: card.id)
        }
        let partial = insightEvent(session: store.sessionID, text: "DO NOT EXPORT", final: false)
        let snapshot = MeetingExportSnapshot(title: "Meeting / ../<title>", startedAt: nil,
                                              microphoneLocale: "ja-JP", systemLocale: "en-US", sessionID: store.sessionID,
                                              events: [event, partial], candidates: candidateStore.items, summary: nil)
        let markdown = snapshot.markdown
        #expect(markdown.contains("## 確認済みの決定"))
        #expect(markdown.contains("## 未確認の候補"))
        #expect(markdown.contains("## 却下した候補"))
        #expect(markdown.contains("[00:00:00 · 内部音声](#utterance-\(event.id.uuidString.lowercased()))"))
        #expect(!markdown.contains("\n# Confirmed"))
        #expect(!markdown.contains("<script>"))
        #expect(!markdown.contains("DO NOT EXPORT"))
        #expect(markdown.contains("開始日時: 未取得"))
        #expect(!snapshot.filename.contains("/"))
        #expect(!snapshot.filename.contains(".."))
    }

    @Test func cancelledAndFailedWritesPreserveLastSuccessfulExport() throws {
        let store = summaryStore(count: 1)
        let snapshot = MeetingExportSnapshot(title: "Test", startedAt: nil, microphoneLocale: "ja", systemLocale: "en",
                                              sessionID: store.sessionID, events: store.finals, candidates: [], summary: nil)
        let exporter = MeetingExportState()
        let url = URL(fileURLWithPath: "/private/tmp/conflingo-pr7-export-test.md")
        var writes = 0
        exporter.save(snapshot, to: nil) { _, _ in writes += 1 }
        #expect(writes == 0)
        #expect(exporter.message.isEmpty)
        exporter.save(snapshot, to: url) { content, target in
            writes += 1
            #expect(content == snapshot.markdown)
            #expect(target == url)
        }
        #expect(exporter.matches(snapshot))
        #expect(exporter.message.contains("書き出しました"))
        exporter.save(snapshot, to: url) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(exporter.message.contains("失敗"))
        #expect(exporter.matches(snapshot))
        #expect(writes == 1)
        exporter.reset()
        #expect(!exporter.matches(snapshot))
    }
}
