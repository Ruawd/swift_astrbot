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

    private var filteredItems: [ResourceItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter {
            $0.title.localizedStandardContains(searchText) || ($0.subtitle?.localizedStandardContains(searchText) ?? false)
        }
    }

    var body: some View {
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
                            HStack(spacing: 12) {
                                statusDot(item.style)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title).fontWeight(.medium)
                                    if let subtitle = item.subtitle {
                                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
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
                if resource.supportsCreate {
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
        } catch let error as APIError {
            if case .unauthorized = error { appState.signOut() }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
