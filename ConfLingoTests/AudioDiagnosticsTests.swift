import Foundation
import Testing
@testable import ConfLingo

struct AudioDiagnosticsTests {
    @Test func countersAreSeparatedFrozenAndResetWithoutContent() throws {
        let diagnostics = AudioDiagnostics()
        diagnostics.begin()
        #expect(diagnostics.snapshot == nil)
        diagnostics.record(.tap, origin: .microphone, samples: 4096, sampleRate: 16000, channels: 1)
        diagnostics.record(.conversionFailure, origin: .microphone)
        diagnostics.record(.consumed, origin: .systemAudio, samples: 1024, sampleRate: 48000, channels: 2)
        diagnostics.record(.finalResult, origin: .microphone)
        diagnostics.mark(.stopStarted)
        diagnostics.finish()
        let first = try #require(diagnostics.snapshot)
        #expect(first.inputs["microphone"]?.counts["tap"] == 1)
        #expect(first.inputs["microphone"]?.sampleCounts["tap"] == 4096)
        #expect(first.inputs["microphone"]?.counts["conversionFailure"] == 1)
        #expect(first.inputs["systemAudio"]?.counts["consumed"] == 1)
        #expect(first.inputs["microphone"]?.counts["consumed"] == nil)
        diagnostics.record(.tap, origin: .microphone)
        #expect(diagnostics.snapshot == first)
        let data = try JSONEncoder().encode(first)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "startedAt", "inputs", "stages"])
        diagnostics.begin()
        diagnostics.finish()
        let next = try #require(diagnostics.snapshot)
        #expect(next.id != first.id && next.inputs.isEmpty)
    }

    @Test func disabledDiagnosticsNeverCollectOrExposeData() {
        let diagnostics = AudioDiagnostics(enabled: false)
        diagnostics.begin()
        diagnostics.record(.tap, origin: .microphone)
        diagnostics.finish()
        #expect(diagnostics.snapshot == nil)
        #expect(AudioDiagnostics.fromEnvironment([:]) == nil)
        #expect(AudioDiagnostics.fromEnvironment(["CONFLINGO_AUDIO_DIAGNOSTICS": "0"]) == nil)
    }

    @Test @MainActor func controllerCountsFinalizationAndStoreAcceptance() async throws {
        let fixture = DualFixture()
        let diagnostics = AudioDiagnostics()
        let controller = fixture.controller(diagnostics: diagnostics)
        await controller.start()
        try await fixture.microphone.emit("sensitive synthetic text", time: 1, final: false)
        try await fixture.microphone.emit("sensitive synthetic text", time: 1)
        try await fixture.system.emit(" ", time: 2)
        fixture.microphone.finalOnStop = "never persist this text"
        await controller.stop()
        let snapshot = try #require(diagnostics.snapshot)
        let microphone = try #require(snapshot.inputs["microphone"])
        #expect(microphone.counts["partialResult"] == 1)
        #expect(microphone.counts["finalResult"] == 2)
        #expect(microphone.counts["normalized"] == 3)
        #expect(microphone.counts["storeAccepted"] == 3)
        #expect(snapshot.inputs["systemAudio"]?.counts["emptyResult"] == 1)
        #expect(controller.store.finals.count == 2)
        #expect(snapshot.stages["deliveryFinished"] != nil)
        let data = try JSONEncoder().encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("sensitive") && !text.contains("never persist"))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try diagnostics.save(to: url)
        #expect(try JSONDecoder().decode(AudioDiagnostics.Snapshot.self, from: Data(contentsOf: url)) == snapshot)
    }

    @Test func concurrentCountersDoNotLoseFramesAndCannotSaveBeforeStop() async throws {
        let diagnostics = AudioDiagnostics()
        diagnostics.begin()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<1000 { diagnostics.record(.tap, origin: .microphone, samples: 256) }
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try diagnostics.save(to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        diagnostics.finish()
        #expect(diagnostics.snapshot?.inputs["microphone"]?.counts["tap"] == 8000)
        #expect(diagnostics.snapshot?.inputs["microphone"]?.sampleCounts["tap"] == 2_048_000)
    }

    @Test @MainActor func storeReportsRejectedUpdatesWithoutChangingAcceptedTranscript() {
        let store = MeetingSessionStore(sessionID: UUID())
        let event = transcriptEvent(sessionID: store.sessionID)
        #expect(store.receive(event))
        #expect(!store.receive(event))
        #expect(!store.receive(transcriptEvent(sessionID: UUID())))
        #expect(store.finals == [event])
    }

    @Test @MainActor func analyzerInputConsumptionIsCountedWithoutRetainingSamples() async throws {
        let diagnostics = AudioDiagnostics()
        diagnostics.begin()
        let capture = StubAudioCapture()
        let source = StubMicrophonePermission().source(capture: capture)
        let speech = SpeechTranscriptionService(audioSource: source, diagnostics: diagnostics)
        let format = try makeFormat()
        let inputs = try await speech.startAudioInput(targetFormat: format)
        try capture.emit([0.25, -0.5], format: format)
        try capture.emit([0.75], format: format)
        try await speech.stopInput()
        var count = 0
        for try await _ in inputs { count += 1 }
        diagnostics.finish()
        let input = try #require(diagnostics.snapshot?.inputs["microphone"])
        #expect(count == 2 && input.counts["consumed"] == 2)
        #expect(input.sampleCounts["consumed"] == 3)
    }
}
