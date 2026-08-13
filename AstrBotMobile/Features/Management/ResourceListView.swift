import SwiftUI

struct ResourceListView: View {
    @Environment(AppState.self) private var appState
    let resource: ManagementResource
    @State private var response: JSONValue?
    @State private var items: [ResourceItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showCreate = false
    @State private var statusResponse: JSONValue?

    private var filteredItems: [ResourceItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) ?? false)
        }
    }

    var body: some View {
        if resource == .logs {
            LiveLogView()
        } else {
            standardContent
        }
    }

    private var standardContent: some View {
        ZStack {
            LiquidBackground()
            Group {
                if let errorMessage {
                    ContentUnavailableView {
                        Label("读取失败", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重试") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                } else if items.isEmpty && !isLoading {
                    if let response {
                        ScrollView {
                            JSONTreeView(value: response)
                                .padding(16)
                        }
                    } else {
                        EmptyStateView(icon: resource.icon, title: "暂无\(resource.title)", description: "服务器没有返回项目")
                    }
                } else {
                    List(filteredItems) { item in
                        NavigationLink {
                            ResourceDetailView(resource: resource, item: item)
                        } label: {
                            ResourceVisualRow(
                                resource: resource,
                                item: item,
                                platformStatus: platformStatus(for: item)
                            )
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if canToggle(item) {
                                Button { Task { await toggle(item) } } label: {
                                    Label(item.style == .enabled ? "停用" : "启用", systemImage: item.style == .enabled ? "pause.fill" : "play.fill")
                                }
                                .tint(item.style == .enabled ? .orange : .green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if resource == .cronJobs {
                                Button { Task { await runCron(item) } } label: { Label("运行", systemImage: "play.fill") }.tint(.blue)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            if isLoading { LoadingOverlay(title: "正在读取\(resource.title)") }
        }
        .navigationTitle(resource.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "搜索")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(isLoading)
                    .accessibilityLabel("刷新")
                if resource.supportsCreate && resource != .bots && resource != .providers && resource != .cronJobs && resource != .knowledgeBases && resource != .personas {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新建")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            RawJSONActionView(
                title: "新建\(resource.title)",
                path: resource.createPath ?? resource.path,
                method: .post,
                initialBody: "{}"
            ) { Task { await load() } }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func statusDot(_ style: ResourceItemStyle) -> some View {
        let color: Color
        switch style {
        case .enabled: color = .green
        case .disabled: color = .secondary
        case .warning: color = .orange
        case .neutral: color = AstrBotPalette.blue
        }
        return Circle().fill(color).frame(width: 9, height: 9).accessibilityHidden(true)
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await client.request(path: resource.path, method: resource.method)
            response = result.data
            items = resource.parseItems(from: result.data)
            if resource == .bots {
                statusResponse = try? await client.request(path: "/api/v1/bots/stats").data
            }
        } catch let error as APIError {
            if case .unauthorized = error { appState.signOut() }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func platformStatus(for item: ResourceItem) -> JSONValue? {
        statusResponse?["platforms"]?.arrayValue?.first(where: { $0["id"]?.stringValue == item.id })
    }

    private func canToggle(_ item: ResourceItem) -> Bool {
        return [.bots, .providers, .plugins, .mcp, .skills, .cronJobs].contains(resource)
    }

    @MainActor
    private func toggle(_ item: ResourceItem) async {
        guard let client = appState.apiClient else { return }
        let enabled = item.style != .enabled
        let request: (String, HTTPMethod, JSONValue)
        switch resource {
        case .bots: request = ("/api/v1/bots/\(encoded(item.id))/enabled", .patch, .object(["enabled": .bool(enabled)]))
        case .providers: request = ("/api/v1/providers/\(encoded(item.id))/enabled", .patch, .object(["enabled": .bool(enabled)]))
        case .plugins: request = ("/api/v1/plugins/\(encoded(item.id))/enabled", .patch, .object(["enabled": .bool(enabled)]))
        case .mcp: request = ("/api/v1/mcp/servers/\(encoded(item.id))/enabled", .patch, .object(["enabled": .bool(enabled)]))
        case .skills: request = ("/api/v1/skills/\(encoded(item.id))", .patch, .object(["enabled": .bool(enabled)]))
        case .cronJobs: request = ("/api/v1/cron/jobs/\(encoded(item.id))", .patch, .object(["enabled": .bool(enabled)]))
        default: return
        }
        do {
            _ = try await client.request(path: request.0, method: request.1, body: request.2)
            appState.showToast(enabled ? "已启用" : "已停用")
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func runCron(_ item: ResourceItem) async {
        guard let client = appState.apiClient else { return }
        do {
            _ = try await client.request(path: "/api/v1/cron/jobs/\(encoded(item.id))/run", method: .post)
            appState.showToast("任务已开始运行", style: .info)
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private struct ResourceVisualRow: View {
    let resource: ManagementResource
    let item: ResourceItem
    let platformStatus: JSONValue?

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(tint.opacity(0.12))
                Image(systemName: resource.icon).foregroundStyle(tint)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(item.title).font(.body.weight(.semibold)).lineLimit(1)
                    statusBadge
                }
                subtitle
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if resource == .bots, let status = platformStatus?["status"]?.stringValue {
            Text(status == "running" ? "运行中" : status)
                .font(.caption2.weight(.bold)).foregroundStyle(status == "running" ? .green : .orange)
        } else if item.style != .neutral {
            Text(item.style == .enabled ? "已启用" : "已停用")
                .font(.caption2.weight(.bold)).foregroundStyle(item.style == .enabled ? .green : .secondary)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        switch resource {
        case .plugins:
            Text("\(item.raw["version"]?.stringValue ?? "") · \(item.raw["author"]?.stringValue ?? "未知作者")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .providers:
            Text("\(item.raw["provider_type"]?.stringValue ?? item.raw["type"]?.stringValue ?? "") · \(item.raw["model"]?.stringValue ?? item.raw["provider"]?.stringValue ?? "")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .cronJobs:
            Text("\(item.raw["cron_expression"]?.stringValue ?? item.raw["run_at"]?.stringValue ?? "未计划") · 下次 \(item.raw["next_run_time"]?.stringValue ?? "—")")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        case .mcp:
            Text(item.raw["connected"]?.stringValue == "true" ? "已连接" : "未连接")
                .font(.caption).foregroundStyle(item.raw["connected"]?.stringValue == "true" ? .green : .secondary)
        case .personas:
            Text(item.raw["system_prompt"]?.stringValue ?? "未设置提示词").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        default:
            if let value = item.subtitle { Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }
    }

    private var tint: Color {
        if resource == .bots, platformStatus?["status"]?.stringValue == "running" { return .green }
        if item.style == .disabled { return .secondary }
        return AstrBotPalette.blue
    }
}
