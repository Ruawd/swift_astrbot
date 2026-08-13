import SwiftUI

struct ResourceDetailView: View {
    let resource: ManagementResource
    let item: ResourceItem
    @State private var showRawAction = false

    var body: some View {
        ZStack {
            LiquidBackground()
            ScrollView {
                VStack(spacing: 16) {
                    GlassCard {
                        HStack(spacing: 14) {
                            Image(systemName: resource.icon)
                                .font(.title2)
                                .foregroundStyle(AstrBotPalette.blue)
                                .frame(width: 48, height: 48)
                                .background(AstrBotPalette.blue.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).font(.title3.bold())
                                if let subtitle = item.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                        }
                    }
                    JSONTreeView(value: item.raw)
                    GlassCard {
                        Text("高级操作").font(.headline)
                        Text("所有资源的完整增删改查均可通过接口浏览器执行。路径参数会在发送前提示填写。")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                        Button("在接口浏览器中打开") { showRawAction = true }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showRawAction) {
            RawJSONActionView(title: item.title, path: resource.path, method: .get, initialBody: item.raw.prettyPrinted)
        }
    }
}

struct JSONTreeView: View {
    let value: JSONValue

    var body: some View {
        GlassCard {
            switch value {
            case let .object(object):
                VStack(spacing: 0) {
                    ForEach(object.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top) {
                            Text(key).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            Spacer(minLength: 12)
                            Text(object[key]?.stringValue ?? compact(object[key]))
                                .font(.subheadline)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 8)
                        if key != object.keys.sorted().last { Divider() }
                    }
                }
            default:
                Text(value.prettyPrinted)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func compact(_ value: JSONValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case let .array(array): return "[\(array.count) 项]"
        case let .object(object): return "{\(object.count) 项}"
        case .null: return "null"
        default: return value.prettyPrinted
        }
    }
}
