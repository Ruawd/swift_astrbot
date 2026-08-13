import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var versions: JSONValue = .object([:])
    @State private var showSignOutConfirmation = false
    @State private var showAccountEditor = false

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                Section {
                    HStack(spacing: 14) {
                        AstrBotLogo(size: 54)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.username.isEmpty ? "AstrBot 管理员" : appState.username).font(.headline)
                            Text("\(appState.authMode.title) · AstrBot \(versions["astrbot_version"]?.stringValue ?? "—")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section("WebUI 设置") {
                    ForEach([SettingsSection.general, .appearance, .network, .security]) { section in
                        NavigationLink(value: section) {
                            SettingsNavigationLabel(section: section, subtitle: sectionSubtitle(section))
                        }
                    }
                }

                Section {
                    NavigationLink(value: SettingsSection.maintenance) {
                        SettingsNavigationLabel(section: .maintenance, subtitle: "备份、存储清理和重启")
                    }
                    NavigationLink(value: SettingsSection.openAPI) {
                        SettingsNavigationLabel(section: .openAPI, subtitle: "管理 API Key 和权限范围")
                    }
                    NavigationLink(value: SettingsSection.resources) {
                        SettingsNavigationLabel(section: .resources, subtitle: "版本、文档、FAQ 与开源仓库")
                    }
                }

                Section("账号与本机") {
                    Button { showAccountEditor = true } label: {
                        Label("修改 AstrBot 账号", systemImage: "person.badge.key")
                    }
                    Button { authenticateWithBiometrics() } label: {
                        Label("测试 Face ID / Touch ID", systemImage: "faceid")
                    }
                    Picker("App 主题", selection: Binding(
                        get: { appState.theme },
                        set: { appState.updateTheme($0) }
                    )) {
                        ForEach(AppState.Theme.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    Button(role: .destructive) { showSignOutConfirmation = true } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .navigationDestination(for: SettingsSection.self) { section in
            switch section {
            case .general, .appearance, .network, .security:
                SystemSettingsView(section: section)
            case .maintenance:
                MaintenanceSettingsView()
            case .openAPI:
                APIKeySettingsView()
            case .resources:
                ResourceLinksView(versions: versions)
            }
        }
        .task { await loadVersions() }
        .confirmationDialog("确认退出当前 AstrBot？", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { appState.signOut() }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAccountEditor) { AccountEditorView() }
    }

    private func sectionSubtitle(_ section: SettingsSection) -> String {
        switch section {
        case .general: return "运行时、日志和临时存储"
        case .appearance: return "文本转图片及显示偏好"
        case .network: return "代理、PyPI 与网络访问"
        case .security: return "HTTPS、限流和两步验证"
        default: return ""
        }
    }

    @MainActor
    private func loadVersions() async {
        guard let client = appState.apiClient else { return }
        do { versions = try await client.request(path: "/api/v1/stats/versions", authenticated: false).data ?? .object([:]) }
        catch { /* Non-critical metadata. */ }
    }

    private func authenticateWithBiometrics() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            appState.showToast("设备未配置生物识别", style: .error)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "验证 AstrBot 管理员身份") { success, error in
            Task { @MainActor in
                appState.showToast(success ? "验证成功" : (error?.localizedDescription ?? "验证失败"), style: success ? .success : .error)
            }
        }
    }
}

private struct SettingsNavigationLabel: View {
    let section: SettingsSection
    let subtitle: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: section.icon).foregroundStyle(AstrBotPalette.blue).frame(width: 30)
        }
        .padding(.vertical, 4)
    }
}

private struct MaintenanceSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showRestartConfirmation = false
    @State private var isWorking = false

    var body: some View {
        ZStack {
            LiquidBackground()
            List {
                Section("数据维护") {
                    NavigationLink { BackupView() } label: {
                        Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                    }
                    NavigationLink { StorageView() } label: {
                        Label("存储空间", systemImage: "internaldrive")
                    }
                    NavigationLink { LiveLogView() } label: {
                        Label("实时控制台", systemImage: "terminal")
                    }
                }
                Section("系统") {
                    Button(role: .destructive) { showRestartConfirmation = true } label: {
                        Label("重启 AstrBot", systemImage: "power")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            if isWorking { LoadingOverlay(title: "正在执行系统操作") }
        }
        .navigationTitle("维护")
        .confirmationDialog("确认重启 AstrBot？", isPresented: $showRestartConfirmation, titleVisibility: .visible) {
            Button("重启", role: .destructive) { Task { await restart() } }
            Button("取消", role: .cancel) {}
        } message: { Text("重启期间机器人会短暂离线。") }
    }

    @MainActor
    private func restart() async {
        guard let client = appState.apiClient else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.request(path: "/api/v1/system/restart", method: .post)
            appState.showToast("已发送重启指令", style: .info)
        } catch { appState.showToast(error.localizedDescription, style: .error) }
    }
}

private struct ResourceLinksView: View {
    @Environment(\.openURL) private var openURL
    let versions: JSONValue

    var body: some View {
        List {
            Section("版本") {
                LabeledContent("AstrBot", value: versions["astrbot_version"]?.stringValue ?? "—")
                LabeledContent("WebUI", value: versions["webui_version"]?.stringValue ?? "—")
            }
            Section("资源") {
                Button { openURL(URL(string: "https://docs.astrbot.app")!) } label: { Label("使用文档", systemImage: "book") }
                Button { openURL(URL(string: "https://docs.astrbot.app/faq.html")!) } label: { Label("常见问题", systemImage: "questionmark.circle") }
                Button { openURL(URL(string: "https://github.com/AstrBotDevs/AstrBot")!) } label: { Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right") }
            }
        }
        .navigationTitle("资源")
    }
}

private struct AccountEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var currentPassword = ""
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("验证身份") { SecureField("当前密码", text: $currentPassword).textContentType(.password) }
                Section("账号") {
                    TextField("新用户名（可留空）", text: $newUsername)
                        .textContentType(.username).textInputAutapitalizationDisabled()
                }
                Section("新密码") {
                    SecureField("新密码（可留空）", text: $newPassword).textContentType(.newPassword)
                    SecureField("确认新密码", text: $confirmPassword).textContentType(.newPassword)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("修改账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || currentPassword.isEmpty || (!newPassword.isEmpty && newPassword != confirmPassword))
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard let client = appState.apiClient else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            var payload: [String: JSONValue] = ["password": .string(currentPassword)]
            if !newUsername.isEmpty { payload["new_username"] = .string(newUsername) }
            if !newPassword.isEmpty {
                payload["new_password"] = .string(newPassword)
                payload["confirm_password"] = .string(confirmPassword)
            }
            _ = try await client.request(path: "/api/v1/auth/account", method: .patch, body: .object(payload))
            appState.showToast("账号已更新，请重新登录")
            appState.signOut()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private extension View {
    func textInputAutapitalizationDisabled() -> some View {
        textInputAutocapitalization(.never).autocorrectionDisabled()
    }
}
