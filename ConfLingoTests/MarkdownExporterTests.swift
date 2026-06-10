import Foundation
import Testing
@testable import ConfLingo

struct MarkdownExporterTests {
    private let date = Date(timeIntervalSince1970: 1_780_000_000)

    private func segment(
        index: Int,
        english: String,
        japanese: String?,
        startTime: TimeInterval? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID(),
            index: index,
            english: english,
            japanese: japanese,
            translationState: japanese == nil ? .pending : .done,
            finalizedAt: date,
            startTime: startTime
        )
    }

    @Test func rendersFullSessionWithTranslatedAndUntranslated() {
        let segments = [
            segment(index: 1, english: "Hello everyone.", japanese: "皆さんこんにちは。"),
            segment(index: 2, english: "Welcome to the conference.", japanese: nil),
        ]
        let markdown = MarkdownExporter.render(
            sessionName: "WWDC Keynote",
            date: date,
            segments: segments,
            sourceLanguage: "en-US",
            targetLanguage: "ja"
        )

        let dateString = MarkdownExporter.dateFormatter.string(from: date)
        let expected = """
        # ConfLingo Session: WWDC Keynote

        - Date: \(dateString)
        - Source language: en-US
        - Target language: ja
        - Segments: 2

        ## Transcript

        ### Segment 1

        English:
        Hello everyone.

        Japanese:
        皆さんこんにちは。

        ### Segment 2

        English:
        Welcome to the conference.

        Japanese:
        (untranslated)
        """
        #expect(markdown == expected)
    }

    @Test func emptySessionNameFallsBackToUntitled() {
        let markdown = MarkdownExporter.render(
            sessionName: "  ", date: date, segments: [],
            sourceLanguage: "en-US", targetLanguage: "ja"
        )
        #expect(markdown.hasPrefix("# ConfLingo Session: Untitled"))
    }

    @Test func emptySegmentsRendersHeaderOnly() {
        let markdown = MarkdownExporter.render(
            sessionName: "Empty", date: date, segments: [],
            sourceLanguage: "en-US", targetLanguage: "ja"
        )
        #expect(markdown.contains("- Segments: 0"))
        #expect(!markdown.contains("### Segment"))
    }

    @Test func rendersSelectedLanguagePair() {
        let markdown = MarkdownExporter.render(
            sessionName: "中国語セッション", date: date, segments: [],
            sourceLanguage: "zh-Hans", targetLanguage: "ko"
        )
        #expect(markdown.contains("- Source language: zh-Hans"))
        #expect(markdown.contains("- Target language: ko"))
    }

    @Test func transcriptionOnlyOmitsTargetLanguageAndJapaneseBlocks() {
        let segments = [
            segment(index: 1, english: "Hello everyone.", japanese: nil),
            segment(index: 2, english: "Welcome to the conference.", japanese: nil),
        ]
        let markdown = MarkdownExporter.render(
            sessionName: "Transcription Only",
            date: date,
            segments: segments,
            sourceLanguage: "en-US",
            targetLanguage: nil
        )

        let dateString = MarkdownExporter.dateFormatter.string(from: date)
        let expected = """
        # ConfLingo Session: Transcription Only

        - Date: \(dateString)
        - Source language: en-US
        - Segments: 2

        ## Transcript

        ### Segment 1

        English:
        Hello everyone.

        ### Segment 2

        English:
        Welcome to the conference.
        """
        #expect(markdown == expected)
        #expect(!markdown.contains("- Target language:"))
        #expect(!markdown.contains("Japanese:"))
    }

    @Test func timestampFormatsAsHoursMinutesSeconds() {
        #expect(MarkdownExporter.timestamp(0) == "00:00:00")
        #expect(MarkdownExporter.timestamp(225) == "00:03:45")
        #expect(MarkdownExporter.timestamp(3725) == "01:02:05")
        #expect(MarkdownExporter.timestamp(59.9) == "00:00:59")
    }

    @Test func segmentHeadingIncludesTimestampWhenAvailable() {
        let segments = [
            segment(index: 1, english: "Hello.", japanese: nil, startTime: 225.0),
            segment(index: 2, english: "World.", japanese: nil),
        ]
        let markdown = MarkdownExporter.render(
            sessionName: "Minutes",
            date: date,
            segments: segments,
            sourceLanguage: "en-US",
            targetLanguage: nil
        )
        #expect(markdown.contains("### Segment 1 [00:03:45]"))
        // startTime 不明のセグメントは従来どおりの見出し
        #expect(markdown.contains("### Segment 2\n"))
        #expect(!markdown.contains("### Segment 2 ["))
    }
}
