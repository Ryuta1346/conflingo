import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct VocabularyLifecycleTests {
    @Test func vocabularyAndLiveUpdatesReachBothInputsWithoutRestart() async throws {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(recognitionMode: .vocabulary,
            contextKeywords: [.microphone: ["Photon"], .systemAudio: ["refunding"]])
        #expect(controller.phase == .listening)
        #expect(fixture.microphone.preparedMode == .vocabulary)
        #expect(fixture.microphone.keywords == ["Photon"])
        #expect(fixture.system.keywords == ["refunding"])
        let updated = await controller.updateContext([.microphone: ["NewTerm"], .systemAudio: ["NewTerm"]])
        #expect(updated)
        #expect(fixture.microphone.keywords == ["NewTerm"])
        #expect(fixture.microphone.starts == 1 && fixture.system.starts == 1)
        #expect(fixture.microphone.inputStops == 0)
        await controller.stop()
    }

    @Test func failedLiveContextDoesNotStopAudio() async {
        let fixture = DualFixture()
        let controller = fixture.controller()
        await controller.start(recognitionMode: .vocabulary)
        fixture.system.contextFails = true
        #expect(!(await controller.updateContext([.microphone: ["one"], .systemAudio: ["two"]])))
        #expect(controller.phase == .listening)
        #expect(fixture.microphone.inputStops == 0)
        await controller.stop()
    }
}
