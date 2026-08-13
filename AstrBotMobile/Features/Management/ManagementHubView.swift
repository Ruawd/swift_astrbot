import SwiftUI

struct ManagementHubView: View {
    @State private var searchText = ""

    private let webUIOrder = [
        "bots", "providers", "plugins", "profiles", "knowledge", "personas",
        "conversations", "sessions", "cron", "subagents", "tools", "commands",
        "mcp", "skills", "t2i",
    ]

    private var filtered: [ManagementResource] {
        let visible = ManagementResource.all.filter { webUIOrder.contains($0.id) }
        let ordered = visible.sorted {
            (webUIOrder.firstIndex(of: $0.id) ?? Int.max) < (webUIOrder.firstIndex(of: $1.id) ?? Int.max)
        }
        guard !searchText.isEmpty else { return ordered }
        return ordered.filter {
            $0.title.localizedStandardContains(searchText) ||
                $0.subtitle.localizedStandardContains(searchText) ||
                $0.category.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                ForEach(["核心配置", "数据与自动化", "扩展能力"], id: \.self) { category in
                    if filtered.contains(where: { $0.category == category }) {
                    Section(category) {
                        ForEach(filtered.filter { $0.category == category }) { resource in
                            NavigationLink(value: resource) {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(resource.title).fontWeight(.semibold)
                                        Text(resource.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                } icon: {
                                    Image(systemName: resource.icon)
                                        .foregroundStyle(AstrBotPalette.blue)
                                        .frame(width: 32)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AstrBot 管理")
        .searchable(text: $searchText, prompt: "搜索管理功能")
        .navigationDestination(for: ManagementResource.self) { resource in
            ResourceListView(resource: resource)
        }
    }
}
