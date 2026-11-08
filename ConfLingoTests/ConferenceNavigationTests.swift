import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ConferenceNavigationTests {
    @Test func idleNavigationKeepsTranscriptAndPendingTranslation() {
        let navigation = ConferenceNavigation()
        let store = SessionStore()
        store.sessionName = "保存前の会話"
        let id = store.appendFinal("Keep this sentence.")!
        let unit = store.bufferSegment(id)!
        navigation.request(.setup, phase: store.phase)
        navigation.request(.live, phase: store.phase)
        navigation.request(.settings, phase: store.phase)
        #expect(navigation.destination == .settings)
        #expect(store.sessionName == "保存前の会話")
        #expect(store.segments.first?.id == id)
        #expect(store.untranslatedUnits.first?.id == unit.id)
        store.applyTranslation(id: unit.id, japanese: "この文を保持します。")
        navigation.request(.live, phase: store.phase)
        #expect(store.units.first?.japanese == "この文を保持します。")
    }

    @Test func cancellingNavigationDoesNotStopOrDiscard() {
        let navigation = ConferenceNavigation(destination: .live)
        let store = SessionStore()
        store.phase = .listening
        store.appendFinal("Keep recording.")
        navigation.request(.settings, phase: store.phase)
        #expect(navigation.showsStopConfirmation)
        #expect(navigation.destination == .live)
        navigation.cancelNavigation()
        #expect(!navigation.showsStopConfirmation)
        #expect(navigation.destination == .live)
        #expect(store.phase == .listening)
        #expect(store.segments.count == 1)
    }

    @Test func navigationWaitsForStopAndRejectsConcurrentRequests() async {
        let navigation = ConferenceNavigation(destination: .live)
        let store = SessionStore()
        store.phase = .listening
        let entered = TestSignal()
        let gate = TestGate()
        navigation.request(.setup, phase: store.phase)
        let task = Task {
            await navigation.confirmNavigation(store: store) {
                store.phase = .stopping
                entered.signal()
                await gate.wait()
                store.phase = .idle
            }
        }
        await entered.next()
        await gate.entered.next()
        navigation.request(.home, phase: store.phase)
        #expect(navigation.destination == .live)
        gate.release()
        await task.value
        #expect(navigation.destination == .setup)
    }

    @Test func failedStopRetainsLiveAndCanRetry() async {
        let navigation = ConferenceNavigation(destination: .live)
        let store = SessionStore()
        store.phase = .listening
        navigation.request(.setup, phase: store.phase)
        await navigation.confirmNavigation(store: store) { store.phase = .stopping }
        #expect(navigation.destination == .live)
        #expect(!navigation.showsStopConfirmation)
        navigation.request(.home, phase: store.phase)
        #expect(navigation.destination == .live)
        // The existing transport retries the stop; navigation is requested again after idle.
        store.phase = .idle
        navigation.request(.setup, phase: store.phase)
        #expect(navigation.destination == .setup)
    }

    @Test func preparingAndStoppingCannotNavigateOrClear() {
        let navigation = ConferenceNavigation(destination: .live)
        let store = SessionStore()
        let controller = SessionController(speechService: DualFakeSpeech())
        store.appendFinal("Retain me.")
        for phase in [SessionPhase.preparing, .stopping] {
            store.phase = phase
            navigation.request(.setup, phase: phase)
            controller.reset(store: store)
            #expect(navigation.destination == .live)
            #expect(!navigation.showsStopConfirmation)
            #expect(store.segments.count == 1)
        }
    }

    @Test func confirmingAfterAnIndependentStopDoesNotStopAgain() async {
        let navigation = ConferenceNavigation(destination: .live)
        let store = SessionStore()
        store.phase = .listening
        navigation.request(.settings, phase: store.phase)
        store.phase = .idle
        var calls = 0
        await navigation.confirmNavigation(store: store) { calls += 1 }
        #expect(calls == 0)
        #expect(navigation.destination == .settings)
    }
}
