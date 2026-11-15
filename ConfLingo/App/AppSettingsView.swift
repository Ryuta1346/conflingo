import SwiftUI

struct AppSettingsView: View {
    let composition: AppComposition
    @AppStorage private var fontSize: Double
    @AppStorage private var alwaysOnTop: Bool
    @AppStorage private var appearance: String
    @State private var showsDictionary = false
    @Environment(\.openWindow) private var openWindow

    init(composition: AppComposition) {
        self.composition = composition
        _fontSize = AppStorage(wrappedValue: 16, "fontSize", store: composition.defaults)
        _alwaysOnTop = AppStorage(wrappedValue: false, "alwaysOnTop", store: composition.defaults)
        _appearance = AppStorage(wrappedValue: "system", "appearance", store: composition.defaults)
    }

    var body: some View {
        SettingsView(fontSize: $fontSize, alwaysOnTop: $alwaysOnTop, appearance: $appearance,
            answerLanguage: Binding(get: { composition.meeting.answerLanguage }, set: { composition.meeting.answerLanguage = $0 }),
            llmSettings: composition.meeting.llmSettings, editDictionary: { showsDictionary = true }, prepare: {
                openWindow(id: "main")
                let phase = composition.meeting.phase == .idle ? composition.store.phase : composition.meeting.phase
                composition.navigation.request(.setup, phase: phase)
            })
            .frame(minWidth: 640, idealWidth: 760, minHeight: 520, idealHeight: 720)
            .background(DesignTokens.canvas).foregroundStyle(DesignTokens.text)
            .buttonStyle(AppButtonStyle()).font(DesignTokens.Typography.body)
            .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
            .sheet(isPresented: $showsDictionary) {
                KeywordProfileEditor(profiles: composition.profileStore,
                    canEdit: composition.store.phase == .idle && composition.meeting.phase == .idle)
            }
    }
}
