import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var stats: JSONValue = .object([:])
    @State private var tokenStats: JSONValue = .object([:])
    @State private var versions: JSONValue = .object([:])
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            LiquidBackground()
            ScrollView {
                LazyVStack(spacing: 16) {
                    header
                    if let errorMessage {
                        GlassCard {
                            Label(errorMessage, systemImage: "wifi.exclamationmark")
                                .foregroundStyle(.red)
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.bordered)
                                .padding(.top, 8)
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            title: "累计消息",
                            value: metric(stats["message_count"]),
                            icon: "message.fill",
                            tint: AstrBotPalette.blue
                        )
                        MetricCard(
                            title: "已启用平台",
                            value: metric(stats["platform_count"]),
                            icon: "antenna.radiowaves.left.and.right",
                            tint: .green
                        )
                        MetricCard(
                            title: "插件数量",
                            value: metric(stats["plugin_count"]),
                            icon: "puzzlepiece.extension.fill",
                            tint: .orange
                        )
                        MetricCard(
                            title: "今日 Token",
                            value: metric(tokenStats["today_total_tokens"]),
                            icon: "sparkles",
                            tint: AstrBotPalette.indigo
                        )
                    }
                    systemCard
                    quickActions
                }
                .padding(16)
            }
            .refreshable { await load() }
            if isLoading { LoadingOverlay(title: "正在读取 AstrBot 状态") }
        }
        .navigationTitle("概览")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("刷新")
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AstrBotLogo(size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("你好，\(appState.username.isEmpty ? "管理员" : appState.username)")
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Circle().fill(.green).frame(width: 8, height: 8)
                    Text("AstrBot \(versions["astrbot_version"]?.stringValue ?? "—")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var systemCard: some View {
        GlassCard {
            Text("运行状态").font(.headline)
            VStack(spacing: 13) {
                statusRow("CPU", value: "\(metric(stats["cpu_percent"]))%", icon: "cpu")
                statusRow("进程内存", value: "\(metric(stats["memory"]?["process"])) MB", icon: "memorychip")
                statusRow("线程", value: metric(stats["thread_count"]), icon: "point.3.filled.connected.trianglepath.dotted")
                statusRow("运行时间", value: runningTime, icon: "clock.arrow.circlepath")
            }
            .padding(.top, 8)
        }
    }

    private var quickActions: some View {
        GlassCard {
            Text("快捷管理").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                NavigationLink {
                    ResourceListView(resource: .providers)
                } label: { quickAction("模型提供商", icon: "brain.head.profile") }
                NavigationLink {
                    ResourceListView(resource: .plugins)
                } label: { quickAction("插件", icon: "puzzlepiece.extension") }
                NavigationLink {
                    ResourceListView(resource: .knowledgeBases)
                } label: { quickAction("知识库", icon: "books.vertical") }
                NavigationLink {
                    ResourceListView(resource: .cronJobs)
                } label: { quickAction("定时任务", icon: "calendar.badge.clock") }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private func statusRow(_ title: String, value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }

    private func quickAction(_ title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(AstrBotPalette.blue)
            Text(title).font(.subheadline.weight(.medium))
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(Rectangle())
    }

    private func metric(_ value: JSONValue?) -> String {
        value?.stringValue ?? "—"
    }

    private var runningTime: String {
        guard let value = stats["running"]?.objectValue else { return "—" }
        let hours = value["hours"]?.stringValue ?? "0"
        let minutes = value["minutes"]?.stringValue ?? "0"
        return "\(hours) 小时 \(minutes) 分"
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let statsResponse = client.request(path: "/api/v1/stats")
            async let tokenResponse = client.request(
                path: "/api/v1/stats/provider-tokens",
                query: [URLQueryItem(name: "days", value: "1")]
            )
            async let versionResponse = client.request(path: "/api/v1/stats/versions", authenticated: false)
            stats = try await statsResponse.data ?? .object([:])
            tokenStats = try await tokenResponse.data ?? .object([:])
            versions = try await versionResponse.data ?? .object([:])
        } catch let error as APIError {
            if case .unauthorized = error { appState.signOut() }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
