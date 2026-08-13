import SwiftUI

struct SystemSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let section: SettingsSection
    @State private var config: JSONValue = .object([:])
    @State private var initialConfig: JSONValue = .object([:])
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showRestartConfirmation = false

    private var definitions: [SystemSettingDefinition] {
        SystemSettingDefinition.all.filter { $0.section == section }
    }

    private var groups: [String] {
        Array(Set(definitions.map(\.group))).sorted { first, second in
            definitions.firstIndex(where: { $0.group == first }) ?? 0 < definitions.firstIndex(where: { $0.group == second }) ?? 0
        }
    }

    private var hasChanges: Bool { config != initialConfig }

    var body: some View {
        ZStack {
            LiquidBackground()
            Form {
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(definitions.filter { $0.group == group }) { definition in
                            SettingRow(definition: definition, config: $config)
                        }
                    }
                }
                if section == .general {
                    Section("临时存储") {
                        NavigationLink { StorageView() } label: {
                            Label("查看并清理存储", systemImage: "internaldrive")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            if isLoading || isSaving { LoadingOverlay(title: isSaving ? "正在保存配置" : "正在加载配置") }
        }
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { Task { await save() } }.disabled(!hasChanges || isSaving)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if hasChanges {
                HStack {
                    Label("配置尚未保存", systemImage: "exclamationmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("保存") { Task { await save() } }.buttonStyle(.borderedProminent)
                }
                .padding(12)
                .glassSurface(radius: 18)
                .padding(.horizontal, 12)
            }
        }
        .task { await load() }
        .confirmationDialog("配置已保存", isPresented: $showRestartConfirmation, titleVisibility: .visible) {
            Button("立即重启", role: .destructive) { Task { await restart() } }
            Button("稍后重启", role: .cancel) {}
        } message: { Text("部分系统设置需要重启 AstrBot 后生效。") }
    }

    @MainActor
    private func load() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response = try await client.request(path: "/api/v1/system-config")
            config = response.data?["config"] ?? .object([:])
            initialConfig = config
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await client.request(path: "/api/v1/system-config", method: .put, body: config)
            initialConfig = config
            appState.showToast("系统设置已保存")
            showRestartConfirmation = true
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func restart() async {
        guard let client = appState.apiClient else { return }
        do {
            _ = try await client.request(path: "/api/v1/system/restart", method: .post)
            appState.showToast("AstrBot 正在重启", style: .info)
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

private struct SettingRow: View {
    let definition: SystemSettingDefinition
    @Binding var config: JSONValue

    var body: some View {
        switch definition.kind {
        case .toggle:
            Toggle(isOn: boolBinding) { label }
        case let .choice(options):
            Picker(selection: stringBinding) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            } label: { label }
        case .text:
            VStack(alignment: .leading, spacing: 8) {
                label
                if definition.sensitive {
                    SecureField("输入内容", text: stringBinding)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    TextField("输入内容", text: stringBinding)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            .padding(.vertical, 3)
        case .integer, .decimal:
            VStack(alignment: .leading, spacing: 8) {
                label
                TextField("数值", text: numberBinding)
                    .keyboardType(definition.kind == .integer ? .numberPad : .decimalPad)
            }
            .padding(.vertical, 3)
        case .stringList:
            VStack(alignment: .leading, spacing: 8) {
                label
                TextField("每行一项", text: listBinding, axis: .vertical)
                    .lineLimit(2 ... 6)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            .padding(.vertical, 3)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(definition.title).font(.body)
            Text(definition.subtitle).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stringBinding: Binding<String> {
        Binding(
            get: { config.value(at: definition.keyPath)?.stringValue ?? "" },
            set: { config.setValue(.string($0), at: definition.keyPath) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { config.value(at: definition.keyPath)?.stringValue == "true" },
            set: { config.setValue(.bool($0), at: definition.keyPath) }
        )
    }

    private var numberBinding: Binding<String> {
        Binding(
            get: { config.value(at: definition.keyPath)?.stringValue ?? "" },
            set: {
                if definition.kind == .integer, let number = Int($0) { config.setValue(.number(Double(number)), at: definition.keyPath) }
                else if let number = Double($0) { config.setValue(.number(number), at: definition.keyPath) }
            }
        )
    }

    private var listBinding: Binding<String> {
        Binding(
            get: { config.value(at: definition.keyPath)?.arrayValue?.compactMap(\.stringValue).joined(separator: "\n") ?? "" },
            set: {
                config.setValue(.array($0.split(whereSeparator: \.isNewline).map { .string(String($0)) }), at: definition.keyPath)
            }
        )
    }
}
