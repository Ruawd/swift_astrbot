import SwiftUI

struct ResourceDetailView: View {
    @Environment(AppState.self) private var appState
    let resource: ManagementResource
    let item: ResourceItem

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
                    visualDetails
                }
                .padding(16)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var visualDetails: some View {
        let object = item.raw.objectValue ?? [:]
        switch resource {
        case .plugins:
            DetailSection(title: "插件信息", rows: [
                ("版本", object["version"]?.stringValue ?? "—"),
                ("作者", object["author"]?.stringValue ?? "—"),
                ("仓库", object["repo"]?.stringValue ?? "—"),
                ("安装时间", object["installed_at"]?.stringValue ?? "—"),
                ("状态", object["activated"]?.stringValue == "true" ? "已启用" : "已停用"),
            ])
            if let description = object["desc"]?.stringValue { textSection("说明", description) }
        case .providers:
            DetailSection(title: "模型配置", rows: [
                ("能力", object["provider_type"]?.stringValue ?? "—"),
                ("服务", object["provider"]?.stringValue ?? "—"),
                ("模型", object["model"]?.stringValue ?? object["embedding_model"]?.stringValue ?? "—"),
                ("API 地址", object["api_base"]?.stringValue ?? object["embedding_api_base"]?.stringValue ?? "—"),
                ("超时", "\(object["timeout"]?.stringValue ?? "—") 秒"),
            ])
            Button("测试连接") { Task { await testProvider() } }.buttonStyle(.borderedProminent)
        case .bots:
            DetailSection(title: "平台配置", rows: [
                ("平台 ID", item.id),
                ("适配器", object["type"]?.stringValue ?? "—"),
                ("状态", object["enable"]?.stringValue == "true" ? "已启用" : "已停用"),
            ])
        case .cronJobs:
            DetailSection(title: "计划", rows: [
                ("表达式", object["cron_expression"]?.stringValue ?? "—"),
                ("类型", object["job_type"]?.stringValue ?? "—"),
                ("时区", object["timezone"]?.stringValue ?? "默认"),
                ("下次运行", object["next_run_time"]?.stringValue ?? "—"),
                ("上次运行", object["last_run_at"]?.stringValue ?? "—"),
            ])
            if let description = object["description"]?.stringValue { textSection("任务内容", description) }
        case .personas:
            textSection("系统提示词", object["system_prompt"]?.stringValue ?? "未配置")
            DetailSection(title: "信息", rows: [
                ("人格 ID", item.id),
                ("更新时间", object["updated_at"]?.stringValue ?? "—"),
                ("开场白", "\(object["begin_dialogs"]?.arrayValue?.count ?? 0) 条"),
            ])
        case .mcp:
            DetailSection(title: "连接", rows: [
                ("状态", object["connected"]?.stringValue == "true" ? "已连接" : "未连接"),
                ("命令", object["command"]?.stringValue ?? "—"),
                ("工具", "\(object["tools"]?.arrayValue?.count ?? 0) 个"),
            ])
        case .skills:
            if let description = object["description"]?.stringValue { textSection("说明", description) }
            DetailSection(title: "技能信息", rows: [
                ("来源", object["source_label"]?.stringValue ?? "—"),
                ("类型", object["source_type"]?.stringValue ?? "—"),
                ("只读", object["readonly"]?.stringValue == "true" ? "是" : "否"),
            ])
        default:
            JSONTreeView(value: item.raw)
        }
    }

    private func textSection(_ title: String, _ content: String) -> some View {
        GlassCard {
            Text(title).font(.headline)
            Text(content).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 4)
        }
    }

    @MainActor
    private func testProvider() async {
        guard let client = appState.apiClient else { return }
        do {
            let encoded = item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id
            let response = try await client.request(path: "/api/v1/providers/\(encoded)/test", method: .post)
            let status = response.data?["status"]?.stringValue ?? response.message ?? "测试完成"
            appState.showToast(status)
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

private struct DetailSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        GlassCard {
            Text(title).font(.headline).padding(.bottom, 5)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .top) {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.1).multilineTextAlignment(.trailing).textSelection(.enabled)
                }
                .font(.subheadline)
                .padding(.vertical, 7)
                if index < rows.count - 1 { Divider() }
            }
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
