import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isRestoringSession {
                ProgressView("正在恢复会话…")
            } else if appState.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.snappy, value: appState.isAuthenticated)
        .overlay(alignment: .top) {
            if let toast = appState.toast {
                ToastView(message: toast)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
}
