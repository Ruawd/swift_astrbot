import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("概览", systemImage: "chart.xyaxis.line") }
            NavigationStack { ChatView() }
                .tabItem { Label("聊天", systemImage: "bubble.left.and.bubble.right") }
            NavigationStack { ManagementHubView() }
                .tabItem { Label("管理", systemImage: "slider.horizontal.3") }
            NavigationStack { LiveLogView() }
                .tabItem { Label("日志", systemImage: "terminal") }
            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(AstrBotPalette.blue)
    }
}
