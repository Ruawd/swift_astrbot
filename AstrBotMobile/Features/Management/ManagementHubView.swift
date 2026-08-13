import SwiftUI

struct ManagementHubView: View {
    @State private var searchText = ""

    private var filtered: [ManagementResource] {
        guard !searchText.isEmpty else { return ManagementResource.all }
        return ManagementResource.all.filter {
            $0.title.localizedStandardContains(searchText) ||
                $0.subtitle.localizedStandardContains(searchText) ||
                $0.category.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                ForEach(Array(Dictionary(grouping: filtered, by: \.category).keys).sorted(), id: \.self) { category in
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
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("管理")
        .searchable(text: $searchText, prompt: "搜索管理功能")
        .navigationDestination(for: ManagementResource.self) { resource in
            ResourceListView(resource: resource)
        }
    }
}
