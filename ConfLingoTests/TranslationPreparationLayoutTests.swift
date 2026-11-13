import AppKit
import SwiftUI
import Testing
@testable import ConfLingo

@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct TranslationPreparationLayoutTests {
    @Test(arguments: [560.0, 1100.0])
    func failureAndRecoveryFitWithoutChangingTranscript(width: Double) async throws {
        let coordinator = TranslationCoordinator()
        let store = SessionStore()
        store.phase = .listening
        let id = try #require(store.appendFinal("The transcript continues while translation is unavailable."))
        _ = store.bufferSegment(id)
        let generation = coordinator.beginPreparation()
        coordinator.preparationFailed(generation: generation, reason: "モデルのダウンロードを取り消しました。")
        let host = NSHostingView(rootView: PreparationHarness(coordinator: coordinator, store: store))
        host.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 820),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close(); coordinator.finish() }
        await layout(host)
        #expect(host.frame.width <= width + 1)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = try #require(bitmap.representation(using: .png, properties: [:]))
        try image.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("translation-preparation-\(Int(width)).png"))

        let retry = coordinator.beginPreparation()
        _ = try #require(coordinator.prepared(generation: retry, store: store))
        await layout(host)
        #expect(coordinator.preparationState == .ready)
        #expect(host.frame.width <= width + 1)
        #expect(store.phase == .listening)
        #expect(store.segments.map(\.id) == [id])
    }

    private func layout(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
}

private struct PreparationHarness: View {
    let coordinator: TranslationCoordinator
    let store: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            TranslationPreparationNotice(state: coordinator.preparationState) {
                let generation = coordinator.beginPreparation()
                _ = coordinator.prepared(generation: generation, store: store)
            }
            ConferenceLiveView(store: store, sourceLanguage: "en-US", targetLanguage: "ja", profileName: "Test",
                               fontSize: .constant(24), editSettings: {}, clear: {}, translationPreparation: coordinator.preparationState)
        }
        .background(DesignTokens.canvas)
        .preferredColorScheme(.light)
    }
}
