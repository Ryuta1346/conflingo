import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DualLifecycleTests {
    @Test func stoppingDuringSecondStartCleansUpLateSuccess() async {
        let fixture = DualFixture()
        let gate = TestGate()
        fixture.system.startGate = gate
        let controller = fixture.controller()
        let start = Task { await controller.start() }
        await gate.entered.next()
        #expect(controller.startedInputs == [.microphone])
        let stop = Task { await controller.stop() }
        await gate.cancelled.next()
        #expect(controller.phase == .stopping)
        #expect(fixture.activity.owner == .dualTranscription)
        gate.release()
        await start.value
        await stop.value
        #expect(controller.phase == .idle)
        #expect(fixture.microphone.inputStops == 1)
        #expect(fixture.system.inputStops == 1)
        #expect(fixture.activity.owner == nil)
        #expect(controller.lastError == nil)
        fixture.system.startGate = nil
        await controller.start()
        #expect(controller.phase == .listening)
        await controller.stop()
    }

    @Test func cancellingCallerDuringPreparationDoesNotStartInput() async {
        let fixture = DualFixture()
        let gate = TestGate()
        let controller = fixture.controller(prepareModel: { locale in await gate.wait(); return locale })
        let start = Task { await controller.start() }
        await gate.entered.next()
        start.cancel()
        await gate.cancelled.next()
        gate.release()
        await start.value
        #expect(controller.phase == .idle)
        #expect(controller.lastError == nil)
        #expect(fixture.activity.owner == nil)
        #expect(fixture.microphone.starts + fixture.system.starts == 0)
    }

    @Test func joiningStopCanImmediatelyRestartWithoutRacingCleanup() async {
        for _ in 0..<30 {
            let fixture = DualFixture()
            let controller = fixture.controller()
            await controller.start()
            let gate = TestGate()
            fixture.system.stopGate = gate
            let first = Task { await controller.stop() }
            await gate.entered.next()
            let joining = TestSignal()
            let second = Task {
                joining.signal()
                await controller.stop()
                await controller.start()
            }
            await joining.next()
            gate.release()
            await first.value
            await second.value
            #expect(controller.phase == .listening)
            #expect(fixture.microphone.starts == 2)
            #expect(fixture.system.starts == 2)
            #expect(fixture.activity.owner == .dualTranscription)
            fixture.system.stopGate = nil
            await controller.stop()
        }
    }

    @Test func joiningFailedStopCanRetryWithoutRepeatingSuccessfulSide() async {
        for _ in 0..<30 {
            let fixture = DualFixture()
            let controller = fixture.controller()
            await controller.start()
            let gate = TestGate()
            fixture.system.stopGate = gate
            fixture.system.stopError = .stop
            let first = Task { await controller.stop() }
            await gate.entered.next()
            let joining = TestSignal()
            let second = Task {
                joining.signal()
                await controller.stop()
                fixture.system.stopError = nil
                fixture.system.stopGate = nil
                await controller.stop()
            }
            await joining.next()
            gate.release()
            await first.value
            await second.value
            #expect(controller.phase == .idle)
            #expect(fixture.microphone.inputStops == 1)
            #expect(fixture.system.inputStops == 2)
            #expect(fixture.activity.owner == nil)
        }
    }

    @Test func staleFailureDoesNotStopResumedSessionAndRepeatedStartDoesNotReacquire() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start()
        let staleFailure = fixture.system.onFailure
        await controller.start()
        #expect(fixture.microphone.starts == 1)
        await controller.stop()
        await controller.start()
        staleFailure?(DualFakeSpeech.Failure.recognition)
        #expect(controller.phase == .listening)
        #expect(controller.lastError == nil)
        await controller.stop()
    }

    @Test func competingOwnerRejectsDualBeforeModelPreparation() async {
        let fixture = DualFixture()
        var preparations = 0
        let controller = fixture.controller(prepareModel: { locale in preparations += 1; return locale })
        let token = fixture.activity.acquire(.conference)
        await controller.start()
        #expect(preparations == 0)
        #expect(controller.phase == .idle)
        #expect(controller.lastError?.contains("使用中") == true)
        fixture.activity.release(token)
        await controller.start()
        #expect(controller.phase == .listening)
        await controller.stop()
    }
}
