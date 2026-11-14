import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DualTranscriptionTests {
    @Test func bothInputsKeepOriginsLanguagesAndCommonTime() async throws {
        let fixture = DualFixture()
        var now = 100.0
        let controller = fixture.controller(timeline: MeetingTimeline(now: { now }))
        fixture.microphone.beforeInput = { now = 100 }
        fixture.system.beforeInput = { now = 105 }
        await controller.start(microphoneLocale: Locale(identifier: "ja-JP"), systemLocale: Locale(identifier: "en-US"))
        #expect(controller.phase == .listening)
        try await fixture.system.emit("same", time: 1)
        try await fixture.microphone.emit("sa", time: 2, final: false)
        try await fixture.microphone.emit("same", time: 2)
        await controller.stop()
        #expect(controller.store.finals.map(\.text) == ["same", "same"])
        #expect(controller.store.finals.map(\.origin) == [.microphone, .systemAudio])
        #expect(controller.store.finals.map(\.languageCode) == ["ja-JP", "en-US"])
        #expect(controller.store.finals.map(\.startOffset) == [2, 6])
        #expect(controller.store.finals.first?.revision == 2)
        #expect(controller.store.partials.isEmpty)
    }

    @Test func bothInputsStopBeforeEitherFinalizationIsAwaited() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start()
        fixture.microphone.finishGate = TestGate()
        fixture.microphone.finalOnStop = "last microphone"
        fixture.system.finalOnStop = "last system"
        let stop = Task { await controller.stop() }
        await fixture.microphone.finishGate?.entered.next()
        #expect(fixture.microphone.inputStops == 1)
        #expect(fixture.system.inputStops == 1)
        #expect(controller.phase == .stopping)
        fixture.microphone.finishGate?.release()
        await stop.value
        #expect(Set(controller.store.finals.map(\.text)) == ["last microphone", "last system"])
        #expect(controller.phase == .idle)
    }

    @Test func successivePartialsFinalizeAcrossBothInputsAndStopDrainsLastUtterance() async throws {
        let fixture = DualFixture()
        let controller = fixture.controller(timeline: MeetingTimeline(now: { 0 }))
        await controller.start()
        for index in 0..<9 {
            let text = "System sentence \(index + 1)"
            try await fixture.system.emit(text, time: Double(index), final: false)
            if index == 4 {
                try await fixture.microphone.emit("200ミリ秒、目標100ミリ秒", time: 9, final: false)
            }
            try await fixture.system.emit(text, time: Double(index))
        }
        fixture.microphone.finalOnStop = "200ミリ秒、目標100ミリ秒"
        await controller.stop()
        #expect(controller.store.finals.filter { $0.origin == .systemAudio }.map(\.text)
                == (1...9).map { "System sentence \($0)" })
        #expect(controller.store.finals.filter { $0.origin == .microphone }.map(\.text)
                == ["200ミリ秒、目標100ミリ秒"])
        #expect(controller.store.finals.allSatisfy { $0.isFinal })
        #expect(Set(controller.store.finals.map(\.id)).count == 10)
        #expect(controller.store.partials.isEmpty)
        #expect(controller.phase == .idle)
        #expect(controller.lastError == nil)
    }

    @Test func deniedPermissionAndFailedModelNeverStartEitherInput() async {
        let fixture = DualFixture()
        fixture.microphonePermission.decision = false
        fixture.microphonePermission.status = .undetermined
        let denied = fixture.controller()
        await denied.start()
        #expect(denied.phase == .idle)
        #expect(denied.lastError?.contains("マイク") == true)
        #expect(fixture.microphone.starts + fixture.system.starts == 0)
        let failed = fixture.controller(prepareModel: { _ in throw DualFakeSpeech.Failure.model })
        await failed.start()
        #expect(failed.phase == .idle)
        #expect(failed.lastError != nil)
        #expect(fixture.microphone.starts + fixture.system.starts == 0)
    }

    @Test func cancelDuringModelPreparationRejectsLateSuccessAndReleasesUse() async {
        let fixture = DualFixture()
        let gate = TestGate()
        let controller = fixture.controller(prepareModel: { locale in await gate.wait(); return locale })
        let start = Task { await controller.start() }
        await gate.entered.next()
        let stop = Task { await controller.stop() }
        await gate.cancelled.next()
        #expect(controller.phase == .stopping)
        gate.release()
        await start.value
        await stop.value
        #expect(controller.phase == .idle)
        #expect(fixture.microphone.starts + fixture.system.starts == 0)
        #expect(fixture.activity.owner == nil)
    }

    @Test func partialStartFailureCleansUpBothAndCanRetry() async {
        let fixture = DualFixture()
        fixture.system.startError = .start
        let controller = fixture.controller()
        await controller.start()
        #expect(controller.phase == .idle)
        #expect(fixture.microphone.inputStops == 1)
        #expect(fixture.system.inputStops == 1)
        #expect(controller.lastError?.contains("内部音声") == true)
        fixture.system.startError = nil
        await controller.start()
        #expect(controller.phase == .listening)
        await controller.stop()
    }

    @Test func stopFailureKeepsOwnershipUntilRetryAndStillStopsOtherInput() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start()
        fixture.system.stopError = .stop
        await controller.stop()
        #expect(controller.phase == .stopping)
        #expect(fixture.activity.owner == .dualTranscription)
        #expect(fixture.microphone.inputStops == 1)
        #expect(fixture.system.cancellations == 1)
        #expect(controller.inputState(.microphone) == .idle)
        #expect(controller.inputState(.systemAudio) == .stopping)
        #expect(controller.lastError?.contains("内部音声") == true)
        await controller.start()
        #expect(fixture.system.starts == 1)
        fixture.system.stopError = nil
        await controller.stop()
        #expect(controller.phase == .idle)
        #expect(fixture.activity.owner == nil)
        #expect(fixture.microphone.inputStops == 1)
        #expect(fixture.system.inputStops == 2)
        #expect(controller.inputState(.systemAudio) == .idle)
    }

    @Test func runtimeFailureStopsBothAndPreservesAcceptedFinals() async throws {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start()
        try await fixture.microphone.emit("accepted", time: 1)
        fixture.system.fail(TranscriptEventHub.Failure.overflow)
        await fixture.system.stopping.next()
        await controller.stop()
        #expect(controller.phase == .idle)
        #expect(fixture.microphone.inputStops == 1)
        #expect(controller.store.finals.map(\.text) == ["accepted"])
        #expect(controller.lastError?.contains("欠け") == true)
    }

    @Test func resumeKeepsSessionAndClearRejectsOldCallbacks() async throws {
        let fixture = DualFixture()
        var now = 100.0
        let controller = fixture.controller(timeline: MeetingTimeline(now: { now }))
        await controller.start()
        try await fixture.microphone.emit("first", time: 1)
        let oldReceive = try #require(fixture.microphone.receive)
        let sessionID = controller.store.sessionID
        controller.clear()
        #expect(controller.store.sessionID == sessionID)
        await controller.stop()
        now = 120
        await controller.start()
        try await oldReceive(SpeechResult(text: "stale", isFinal: true, startTime: 1, endTime: 2))
        try await fixture.system.emit("resumed", time: 2)
        await controller.stop()
        #expect(controller.store.sessionID == sessionID)
        #expect(controller.store.finals.map(\.startOffset) == [1, 22])
        controller.clear()
        #expect(controller.store.sessionID != sessionID)
        #expect(controller.store.finals.isEmpty)
        await controller.start()
        try await fixture.microphone.emit("new", time: 1)
        await controller.stop()
        #expect(controller.store.finals.map(\.startOffset) == [1])
    }
}

@MainActor
final class DualFixture {
    let microphone = DualFakeSpeech()
    let system = DualFakeSpeech()
    let microphonePermission = StubMicrophonePermission(status: .granted)
    let activity = AudioInputUse()

    func controller(
        timeline: MeetingTimeline = MeetingTimeline(),
        owner: AudioInputUse.Owner = .dualTranscription,
        diagnostics: AudioDiagnostics? = nil,
        prepareModel: @escaping @MainActor (Locale) async throws -> Locale = { $0 }
    ) -> DualTranscriptionController {
        DualTranscriptionController(
            microphone: microphonePermission.source(capture: StubAudioCapture()),
            systemAudio: SystemAudioSource(capture: StubSystemCapture(), permissionStatus: { .granted }),
            microphoneSpeech: microphone, systemSpeech: system,
            timeline: timeline, activity: activity, owner: owner, diagnostics: diagnostics, prepareModel: prepareModel
        )
    }
}

@MainActor
final class TestGate {
    let entered = TestSignal()
    let cancelled = TestSignal()
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                entered.signal()
            }
        } onCancel: {
            Task { @MainActor in self.cancelled.signal() }
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor
final class DualFakeSpeech: SpeechTranscribing {
    enum Failure: Error { case start, stop, recognition, model }
    var preparedMode: SpeechRecognitionMode = .standard
    var startedLocale: Locale?
    var fastResults = false
    var keywords: [String] = []
    var contextFails = false
    var contextGate: TestGate?
    func prepare(mode: SpeechRecognitionMode, locale: Locale) async throws { preparedMode = mode }
    func updateContext(_ values: [String]) async throws {
        let gate = contextGate
        contextGate = nil
        await gate?.wait()
        if contextFails { throw VocabularyFailure.unavailable }
        keywords = values
    }
    var starts = 0
    var inputStops = 0
    var finishes = 0
    var cancellations = 0
    var startError: Failure?
    var stopError: Failure?
    var startGate: TestGate?
    var finishGate: TestGate?
    var stopGate: TestGate?
    var beforeInput: (() -> Void)?
    var finalOnStop: String?
    let stopping = TestSignal()
    var receive: (@MainActor (SpeechResult) async throws -> Void)?
    var onFailure: (@MainActor (any Error) -> Void)?

    func start(
        locale: Locale, contextKeywords: [String], fastResults: Bool,
        onInputStarted: @escaping @MainActor () -> Void,
        receive: @escaping @MainActor (SpeechResult) async throws -> Void,
        onFailure: @escaping @MainActor (any Error) -> Void
    ) async throws {
        starts += 1
        startedLocale = locale
        self.fastResults = fastResults
        keywords = contextKeywords
        self.receive = receive
        self.onFailure = onFailure
        await startGate?.wait()
        if let startError { throw startError }
        beforeInput?()
        onInputStarted()
    }

    func emit(_ text: String, time: Double, final: Bool = true) async throws {
        try await receive?(SpeechResult(text: text, isFinal: final, startTime: time, endTime: time + 1))
    }
    func fail(_ error: any Error) { onFailure?(error) }
    func stopInput() async throws {
        inputStops += 1
        stopping.signal()
        await stopGate?.wait()
        if let stopError { throw stopError }
    }
    func finishRecognition() async throws {
        finishes += 1
        await finishGate?.wait()
        if let finalOnStop { try await emit(finalOnStop, time: 9) }
    }
    func cancelRecognition() async { cancellations += 1 }
    func stop() async throws {
        try await stopInput()
        try await finishRecognition()
    }
}
