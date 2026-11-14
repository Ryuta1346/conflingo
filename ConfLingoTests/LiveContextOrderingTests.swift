import Foundation
import Testing
@testable import ConfLingo

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LiveContextOrderingTests {
    @Test func newestContextWinsOnBothInputsWhenFirstUpdateIsDelayed() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(recognitionMode: .vocabulary)
        let gate = TestGate()
        fixture.microphone.contextGate = gate
        let first = Task { await controller.updateContext([.microphone: ["Old"], .systemAudio: ["Old"]]) }
        await gate.entered.next()
        let entered = TestSignal()
        let second = Task {
            entered.signal()
            return await controller.updateContext([.microphone: ["New"], .systemAudio: ["New"]])
        }
        await entered.next()
        gate.release()
        _ = await first.value
        #expect(await second.value)
        #expect(fixture.microphone.keywords == ["New"])
        #expect(fixture.system.keywords == ["New"])
        #expect(controller.phase == .listening)
        await controller.stop()
    }

    @Test func stopDrainsOldContextBeforeRestartButStopsAudioImmediately() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(recognitionMode: .vocabulary)
        let gate = TestGate()
        fixture.microphone.contextGate = gate
        let update = Task { await controller.updateContext([.microphone: ["Old"], .systemAudio: ["Old"]]) }
        await gate.entered.next()
        let stop = Task { await controller.stop() }
        await fixture.system.stopping.next()
        #expect(fixture.microphone.inputStops == 1 && fixture.system.inputStops == 1)
        let restart = Task {
            await stop.value
            await controller.start(recognitionMode: .vocabulary, contextKeywords: [.microphone: ["Restart"], .systemAudio: ["Restart"]])
        }
        gate.release()
        #expect(!(await update.value))
        await restart.value
        #expect(fixture.microphone.keywords == ["Restart"] && fixture.system.keywords == ["Restart"])
        await controller.stop()
    }

    @Test func failedInputDoesNotPreventOtherContextOrStopAudio() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(recognitionMode: .vocabulary)
        fixture.microphone.contextFails = true
        #expect(!(await controller.updateContext([.microphone: ["New"], .systemAudio: ["New"]])))
        #expect(fixture.system.keywords == ["New"])
        #expect(controller.phase == .listening)
        fixture.microphone.contextFails = false
        #expect(await controller.updateContext([.microphone: [], .systemAudio: []]))
        #expect(fixture.microphone.keywords.isEmpty && fixture.system.keywords.isEmpty)
        await controller.stop()
    }
}
