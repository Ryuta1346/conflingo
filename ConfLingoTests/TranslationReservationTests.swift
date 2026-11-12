import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized)
struct TranslationReservationTests {
    @Test func partialMeetingReservesSpaceBeforeTranslationEntryExists() async throws {
        let translations = MeetingTranslations(sessionID: UUID(), client: FakeMeetingTranslator())
        let event = TranscriptEvent(id: UUID(), sessionID: translations.sessionID, origin: .systemAudio, languageCode: "en-US",
            startOffset: 1, endOffset: 2, text: "The same words before and after finalization.", isFinal: true, revision: 2, sourceStartTime: 1)
        let host = NSHostingView(rootView: MeetingTranslationText(translations: translations, eventID: event.id,
            fontSize: 24, sourceText: event.text, targetLanguage: "ja").frame(width: 280).fixedSize(horizontal: false, vertical: true))
        let window = makeWindow(host)
        defer { window.close() }
        await layout(host)
        let partialHeight = host.fittingSize.height
        #expect(partialHeight > 70)
        #expect(translations.entries.isEmpty)
        translations.receive(event, targetLanguage: "ja")
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
        let lane = try #require(translations.lanes.first)
        translations.preparationFailed(lane.id, generation: lane.generation, message: "モデル準備に失敗しました")
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
        translations.retry(event.id)
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
    }

    @Test func conferencePreservesRowHeightFromPartialThroughDelayedTranslationAndFailure() async throws {
        let store = SessionStore()
        let source = "A sentence that takes several lines when displayed in a narrow window."
        store.updateVolatile(source)
        let host = NSHostingView(rootView: ConferenceTranslationFixture(store: store))
        let window = makeWindow(host)
        defer { window.close() }
        await layout(host)
        let partialHeight = host.fittingSize.height
        #expect(TranscriptPresentation.translation(store).count == 1)
        let segment = try #require(store.appendFinal(source))
        let unit = try #require(store.bufferSegment(segment))
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
        store.markTranslationFailed(id: unit.id, reason: "unavailable")
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
        store.applyTranslation(id: unit.id, japanese: "狭い画面では数行になる文です。")
        await layout(host)
        #expect(abs(host.fittingSize.height - partialHeight) < 1)
        #expect(TranscriptPresentation.source(store).first?.text == source)
    }

    @Test func conferenceFlushDoesNotCarryBufferedHeightIntoNextPartial() async throws {
        let store = SessionStore()
        let source = String(repeating: "Long buffered words waiting for the next translation unit ", count: 3)
        let segment = try #require(store.appendFinal(source))
        #expect(store.bufferSegment(segment) == nil)
        store.updateVolatile("Next short partial")
        let host = NSHostingView(rootView: ConferenceTranslationFixture(store: store))
        let window = makeWindow(host)
        defer { window.close() }
        await layout(host)

        // The timeout can flush the preceding final while the next partial is still being recognized.
        _ = try #require(store.flushBuffer())
        await layout(host)
        let updatedHeight = host.fittingSize.height
        let freshHost = NSHostingView(rootView: ConferenceTranslationFixture(store: store))
        let freshWindow = makeWindow(freshHost)
        defer { freshWindow.close() }
        await layout(freshHost)

        #expect(TranscriptPresentation.translation(store).count == 2)
        #expect(abs(updatedHeight - freshHost.fittingSize.height) < 1,
                "The next partial must not retain the previous translation unit's reserved space")
    }

    @Test func oversizedTranslationExpandsWithoutTruncationAndDoesNotShrinkOnRetry() async throws {
        let state = ReservationFixtureState()
        let host = NSHostingView(rootView: ReservationFixture(state: state))
        let window = makeWindow(host)
        defer { window.close() }
        await layout(host)
        let initialHeight = host.fittingSize.height
        state.text = String(repeating: "長い訳文を省略せずに表示します。", count: 20)
        await layout(host)
        let expandedHeight = host.fittingSize.height
        #expect(expandedHeight > initialHeight + 200)
        state.text = "再試行中"
        await layout(host)
        #expect(abs(host.fittingSize.height - expandedHeight) < 1)
        state.fontSize = 32
        await layout(host)
        #expect(host.fittingSize.height < expandedHeight)
    }

    @Test(arguments: [16.0, 32.0])
    func meetingTranslationArrivalKeepsReservedHeight(fontSize: Double) async throws {
        let session = UUID()
        let translations = MeetingTranslations(sessionID: session, client: FakeMeetingTranslator())
        let event = TranscriptEvent(id: UUID(), sessionID: session, origin: .systemAudio, languageCode: "en-US",
                                    startOffset: 1, endOffset: 2,
                                    text: "A sentence whose translation arrives later.", isFinal: true,
                                    revision: 1, sourceStartTime: 1)
        translations.receive(event, targetLanguage: "ja")
        let host = NSHostingView(rootView: MeetingTranslationText(translations: translations, eventID: event.id, fontSize: fontSize)
            .frame(width: 280).fixedSize(horizontal: false, vertical: true))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        await layout(host)
        let waiting = host.fittingSize.height
        for lane in translations.lanes { translations.prepared(lane.id, generation: lane.generation) }
        for _ in 0..<10_000 {
            if !translations.isWorking { break }
            await Task.yield()
        }
        await layout(host)
        #expect(translations.completed.count == 1)
        #expect(abs(host.fittingSize.height - waiting) < 1, "Translation should replace reserved content without moving later utterances")
    }

    private func layout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
    }

    private func makeWindow(_ host: NSView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        return window
    }
}

private struct ConferenceTranslationFixture: View {
    let store: SessionStore
    var body: some View {
        VStack(spacing: 0) {
            ForEach(TranscriptPresentation.translation(store)) { entry in
                ReservedTranslation(sourceText: entry.reservationText ?? "", fontSize: 24) {
                    Text(entry.text).font(.system(size: 24)).lineSpacing(6)
                }
            }
        }
        .frame(width: 280).fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor @Observable
private final class ReservationFixtureState {
    var text = "翻訳待ち"
    var fontSize = 16.0
}

private struct ReservationFixture: View {
    let state: ReservationFixtureState
    var body: some View {
        ReservedTranslation(sourceText: "Short source.", fontSize: state.fontSize) {
            Text(state.text).font(.system(size: state.fontSize)).lineSpacing(6)
        }
        .frame(width: 280).fixedSize(horizontal: false, vertical: true)
    }
}
