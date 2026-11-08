import Foundation
import Testing
@testable import ConfLingo

@MainActor
struct ModelAvailabilityTests {
    @Test(arguments: PreparationStub.Stage.allCases)
    func obsoleteCompletionCannotReplaceLatestSelection(stage: PreparationStub.Stage) async {
        let backend = PreparationStub(heldStage: stage)
        let service = ModelAvailabilityService(backend: backend)
        let old = Task { await service.checkAndPrepare(sourceLocaleID: "en-US", targetLanguageID: "ja") }
        await backend.gate.entered.next()
        #expect(await service.checkAndPrepare(sourceLocaleID: "de-DE", targetLanguageID: "en"))
        backend.gate.release()
        #expect(await old.value == false)
        #expect(service.state == .ready)
        #expect(service.speechLocale?.identifier == "de-DE")
        #expect(service.downloadProgress == nil)
    }

    @Test(arguments: [false, true])
    func obsoleteDownloadFailureOrProgressCannotReplaceLatestResult(fails: Bool) async {
        let backend = PreparationStub(heldStage: .speech)
        backend.oldDownloadFails = fails
        let service = ModelAvailabilityService(backend: backend)
        let old = Task { await service.checkAndPrepare(sourceLocaleID: "en-US", targetLanguageID: nil) }
        await backend.gate.entered.next()
        #expect(service.state == .downloadingSpeechModel)
        #expect(await service.checkAndPrepare(sourceLocaleID: "de-DE", targetLanguageID: nil))
        backend.gate.release()
        #expect(await old.value == false)
        #expect(service.state == .ready)
        #expect(service.speechLocale?.identifier == "de-DE")
        #expect(service.downloadProgress == nil)
    }

    @Test(arguments: PreparationStub.Stage.allCases)
    func cancelledPreparationCannotBecomeReady(stage: PreparationStub.Stage) async {
        let backend = PreparationStub(heldStage: stage)
        let service = ModelAvailabilityService(backend: backend)
        let task = Task { await service.checkAndPrepare(sourceLocaleID: "en-US", targetLanguageID: "ja") }
        await backend.gate.entered.next()
        task.cancel()
        backend.gate.release()
        #expect(await task.value == false)
        #expect(service.state != .ready)
    }

    @Test(arguments: PreparationStub.Failure.allCases)
    func latestFailureCanBeRetried(failure: PreparationStub.Failure) async {
        let backend = PreparationStub()
        backend.failure = failure
        let service = ModelAvailabilityService(backend: backend)
        #expect(await service.checkAndPrepare(sourceLocaleID: "en-US", targetLanguageID: "ja") == false)
        guard case .unavailable = service.state else {
            Issue.record("Failed model preparation should be unavailable")
            return
        }
        #expect(service.speechLocale == nil)
        #expect(service.downloadProgress == nil)
        backend.failure = nil
        #expect(await service.checkAndPrepare(sourceLocaleID: "en-US", targetLanguageID: "ja"))
        #expect(service.state == .ready)
    }
}

@MainActor
final class PreparationStub: ModelPreparing {
    enum Stage: CaseIterable { case sources, targets, locale, speech, translation }
    enum Failure: Error, CaseIterable { case locale, speech, download, translation }
    var heldStage: Stage?
    let gate = TestGate()
    var oldDownloadFails = false
    var failure: Failure?

    init(heldStage: Stage? = nil) { self.heldStage = heldStage }

    private func hold(_ stage: Stage) async {
        if heldStage == stage {
            heldStage = nil
            await gate.wait()
        }
    }

    func sourceLocales() async -> [Locale] {
        await hold(.sources)
        return [Locale(identifier: "en-US"), Locale(identifier: "de-DE")]
    }

    func targetLanguages() async -> [Locale.Language] {
        await hold(.targets)
        return [.init(identifier: "ja"), .init(identifier: "en")]
    }

    func supportedLocale(for identifier: String) async -> Locale? {
        await hold(.locale)
        return failure == .locale ? nil : Locale(identifier: identifier)
    }

    func prepareSpeech(for locale: Locale, progress: @escaping @MainActor (Progress) -> Void) async throws -> Bool {
        if heldStage == .speech {
            progress(Progress(totalUnitCount: 100))
            await hold(.speech)
            progress(Progress(totalUnitCount: 200))
            if oldDownloadFails { throw Failure.download }
        }
        if failure == .download {
            progress(Progress(totalUnitCount: 100))
            throw Failure.download
        }
        return failure != .speech
    }

    func supportsTranslation(from source: Locale.Language, to target: Locale.Language) async -> Bool {
        await hold(.translation)
        return failure != .translation
    }
}
