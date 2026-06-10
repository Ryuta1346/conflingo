import SwiftUI

@main
struct ConfLingoApp: App {
    @AppStorage("alwaysOnTop") private var alwaysOnTop = false

    var body: some Scene {
        Window("ConfLingo", id: "main") {
            ContentView()
        }
        .defaultSize(width: 720, height: 560)
        .windowLevel(alwaysOnTop ? .floating : .normal)
    }
}
