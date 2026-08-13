import SwiftUI

struct StorageView: View {
    @Environment(AppState.self) private var appState
    @State private var storage: JSONValue = .object([:])
    @State private var isLoading = true
    @State private var targetToClean: String?

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                Section {
                    HStack(spacing: 20) {
                        storageMetric("日志", item: storage["logs"], color: .orange)
                        storageMetric("缓存", item: storage["cache"], color: AstrBotPalette.blue)
                    }
                    .padding(.vertical, 10)
                    LabeledContent("总占用", value: formatBytes(storage["total_bytes"]))
                }
                Section("清理") {
                    Button { targetToClean = "logs" } label: {
                        Label("清理日志", systemImage: "doc.text")
                    }
                    Button { targetToClean = "cache" } label: {
                        Label("清理缓存", systemImage: "shippingbox")
                    }
                    Button(role: .destructive) { targetToClean = "all" } label: {
                        Label("全部清理", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            if isLoading { LoadingOverlay(title: "正在统计存储") }
        }
        .navigationTitle("存储空间")
        .task { await load() }
        .confirmationDialog("确认清理？", isPresented: Binding(
            get: { targetToClean != nil },
            set: { if !$0 { targetToClean = nil } }
        ), titleVisibility: .visible) {
            Button("清理", role: .destructive) { if let targetToClean { Task { await cleanup(targetToClean) } } }
            Button("取消", role: .cancel) { targetToClean = nil }
        } message: { Text("被清理的文件无法恢复。") }
    }

    private func storageMetric(_ title: String, item: JSONValue?, color: Color) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                Circle().trim(from: 0, to: progress(item)).stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: title == "日志" ? "doc.text" : "shippingbox").foregroundStyle(color)
            }
            .frame(width: 76, height: 76)
            Text(title).font(.subheadline.weight(.semibold))
            Text(formatBytes(item?["size_bytes"])).font(.caption).foregroundStyle(.secondary)
            Text("\(item?["file_count"]?.stringValue ?? "0") 个文件").font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func progress(_ item: JSONValue?) -> Double {
        let itemSize = Double(item?["size_bytes"]?.stringValue ?? "") ?? 0
        let total = Double(storage["total_bytes"]?.stringValue ?? "") ?? 1
        return max(0.04, min(itemSize / max(total, 1), 1))
    }

    private func formatBytes(_ value: JSONValue?) -> String {
        let bytes = Int64(Double(value?.stringValue ?? "") ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do { storage = try await client.request(path: "/api/v1/stats/storage").data ?? .object([:]) }
        catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func cleanup(_ target: String) async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false; targetToClean = nil }
        do {
            _ = try await client.request(path: "/api/v1/stats/storage/cleanup", method: .post, body: .object(["target": .string(target)]))
            appState.showToast("清理完成")
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

struct BackupView: View {
    @Environment(AppState.self) private var appState
    @State private var backups: [ResourceItem] = []
    @State private var isLoading = true
    @State private var backupToDelete: ResourceItem?

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                if backups.isEmpty && !isLoading {
                    ContentUnavailableView("暂无备份", systemImage: "externaldrive", description: Text("点击右上角创建服务器备份"))
                }
                ForEach(backups) { backup in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "shippingbox.fill").foregroundStyle(AstrBotPalette.blue)
                            Text(backup.title).fontWeight(.semibold).lineLimit(1)
                            Spacer()
                            Menu { Button("删除", role: .destructive) { backupToDelete = backup } } label: { Image(systemName: "ellipsis") }
                        }
                        if let object = backup.raw.objectValue {
                            HStack {
                                Text(object["created_at"]?.stringValue ?? "")
                                Spacer()
                                if let size = object["size"] ?? object["size_bytes"] { Text(formatBytes(size)) }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .scrollContentBackground(.hidden)
            if isLoading { LoadingOverlay(title: "正在加载备份") }
        }
        .navigationTitle("备份与恢复")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await create() } } label: { Label("创建", systemImage: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("删除这个备份？", isPresented: Binding(
            get: { backupToDelete != nil }, set: { if !$0 { backupToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let backupToDelete { Task { await delete(backupToDelete) } } }
            Button("取消", role: .cancel) { backupToDelete = nil }
        }
    }

    private func formatBytes(_ value: JSONValue) -> String {
        let bytes = Int64(Double(value.stringValue ?? "") ?? 0)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.request(path: "/api/v1/backups", query: [URLQueryItem(name: "page_size", value: "100")])
            backups = ManagementResource.backups.parseItems(from: response.data)
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func create() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await client.request(path: "/api/v1/backups", method: .post, body: .object([:]))
            appState.showToast("备份任务已创建", style: .info)
            try? await Task.sleep(for: .seconds(2))
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func delete(_ item: ResourceItem) async {
        guard let client = appState.apiClient else { return }
        do {
            let encoded = item.title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.title
            _ = try await client.request(path: "/api/v1/backups/\(encoded)", method: .delete)
            backupToDelete = nil
            appState.showToast("备份已删除")
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

struct APIKeySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var keys: [ResourceItem] = []
    @State private var showCreate = false
    @State private var keyToDelete: ResourceItem?

    var body: some View {
        List {
            Section {
                Text("API Key 用于外部应用访问 AstrBot。密钥只在创建时显示一次。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("访问密钥") {
                if keys.isEmpty { Text("暂无 API Key").foregroundStyle(.secondary) }
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(key.title).fontWeight(.semibold)
                            Spacer()
                            Text(key.raw["revoked_at"] == nil ? "有效" : "已吊销")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(key.raw["revoked_at"] == nil ? Color.green : Color.secondary)
                        }
                        Text(key.raw["key_prefix"]?.stringValue ?? key.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        HStack {
                            Text(key.raw["scopes"]?.arrayValue?.compactMap(\.stringValue).joined(separator: ", ") ?? "无权限")
                            Spacer()
                            Menu {
                                Button("吊销") { Task { await revoke(key) } }
                                Button("删除", role: .destructive) { keyToDelete = key }
                            } label: { Image(systemName: "ellipsis") }
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("OpenAPI")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showCreate = true } label: { Image(systemName: "plus") } } }
        .task { await load() }
        .sheet(isPresented: $showCreate) { CreateAPIKeyView { Task { await load() } } }
        .confirmationDialog("删除这个 API Key？", isPresented: Binding(
            get: { keyToDelete != nil }, set: { if !$0 { keyToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) { if let keyToDelete { Task { await delete(keyToDelete) } } }
            Button("取消", role: .cancel) { keyToDelete = nil }
        }
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        do { keys = ManagementResource.apiKeys.parseItems(from: try await client.request(path: "/api/v1/api-keys").data) }
        catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func revoke(_ item: ResourceItem) async {
        guard let client = appState.apiClient else { return }
        do {
            _ = try await client.request(path: "/api/v1/api-keys/\(item.id)/revoke", method: .post)
            appState.showToast("API Key 已吊销")
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }

    @MainActor
    private func delete(_ item: ResourceItem) async {
        guard let client = appState.apiClient else { return }
        do {
            _ = try await client.request(path: "/api/v1/api-keys/\(item.id)", method: .delete)
            keyToDelete = nil
            appState.showToast("API Key 已删除")
            await load()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

private struct CreateAPIKeyView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onCreated: () -> Void
    @State private var name = ""
    @State private var expires = 90
    @State private var scopes = Set(["chat", "data", "file"])
    @State private var createdKey: String?

    private let options = ["system", "config", "bot", "provider", "chat", "chat:admin", "data", "file", "plugin", "mcp", "skill"]

    var body: some View {
        NavigationStack {
            Form {
                if let createdKey {
                    Section("请立即复制") {
                        Text(createdKey).font(.footnote.monospaced()).textSelection(.enabled)
                        ShareLink(item: createdKey) { Label("分享或保存", systemImage: "square.and.arrow.up") }
                    }
                } else {
                    Section("基本信息") {
                        TextField("名称", text: $name)
                        Stepper("有效期：\(expires) 天", value: $expires, in: 1 ... 3650)
                    }
                    Section("权限范围") {
                        ForEach(options, id: \.self) { scope in
                            Toggle(scope, isOn: Binding(
                                get: { scopes.contains(scope) },
                                set: { isEnabled in
                                    if isEnabled {
                                        scopes.insert(scope)
                                    } else {
                                        scopes.remove(scope)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("创建 API Key")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(createdKey == nil ? "取消" : "完成") { dismiss() } }
                if createdKey == nil {
                    ToolbarItem(placement: .confirmationAction) { Button("创建") { Task { await create() } }.disabled(name.isEmpty || scopes.isEmpty) }
                }
            }
        }
    }

    @MainActor
    private func create() async {
        guard let client = appState.apiClient else { return }
        do {
            let response = try await client.request(path: "/api/v1/api-keys", method: .post, body: .object([
                "name": .string(name), "expires_in_days": .number(Double(expires)),
                "scopes": .array(scopes.sorted().map(JSONValue.string)),
            ]))
            createdKey = response.data?["api_key"]?.stringValue ?? response.data?["key"]?.stringValue
            onCreated()
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}
