import SwiftUI

@main
struct AstrBotMobileApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(appState.preferredColorScheme)
        }
    }
}
