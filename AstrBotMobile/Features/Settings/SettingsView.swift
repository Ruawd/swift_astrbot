import LocalAuthentication
import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var versions: JSONValue = .object([:])
    @State private var showSignOutConfirmation = false
    @State private var showRestartConfirmation = false
    @State private var showAccountEditor = false
    @State private var isWorking = false

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            LiquidBackground()
            Form {
                Section {
                    HStack(spacing: 14) {
                        AstrBotLogo(size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appState.username.isEmpty ? "AstrBot 管理员" : appState.username).font(.headline)
                            Text(appState.authMode.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("连接") {
                    LabeledContent("服务器") {
                        Text(appState.serverURLText).lineLimit(1).foregroundStyle(.secondary)
                    }
                    LabeledContent("AstrBot", value: versions["astrbot_version"]?.stringValue ?? "—")
                    LabeledContent("WebUI", value: versions["webui_version"]?.stringValue ?? "—")
                }
                Section("外观") {
                    Picker("主题", selection: Binding(
                        get: { appState.theme },
                        set: { appState.updateTheme($0) }
                    )) {
                        ForEach(AppState.Theme.allCases) { theme in Text(theme.title).tag(theme) }
                    }
                }
                Section("安全与账号") {
                    Button { showAccountEditor = true } label: { Label("修改账号或密码", systemImage: "person.badge.key") }
                    NavigationLink {
                        ResourceListView(resource: .apiKeys)
                    } label: { Label("API Keys", systemImage: "key.horizontal") }
                    Button {
                        authenticateWithBiometrics()
                    } label: { Label("测试 Face ID / Touch ID", systemImage: "faceid") }
                }
                Section("系统") {
                    NavigationLink { ResourceListView(resource: .backups) } label: {
                        Label("备份与恢复", systemImage: "externaldrive.badge.timemachine")
                    }
                    NavigationLink { ResourceListView(resource: .storage) } label: {
                        Label("存储空间", systemImage: "internaldrive")
                    }
                    NavigationLink { ResourceListView(resource: .logs) } label: {
                        Label("运行日志", systemImage: "doc.text.magnifyingglass")
                    }
                    Button(role: .destructive) { showRestartConfirmation = true } label: {
                        Label("重启 AstrBot", systemImage: "power")
                    }
                }
                Section {
                    Button(role: .destructive) { showSignOutConfirmation = true } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity)
                    }
                }
                Section {
                    Text("AstrBot Mobile · SwiftUI · iOS 26 Liquid Glass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            if isWorking { LoadingOverlay(title: "正在执行系统操作") }
        }
        .navigationTitle("设置")
        .task { await loadVersions() }
        .confirmationDialog("确认退出当前 AstrBot？", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { appState.signOut() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("确认重启 AstrBot？", isPresented: $showRestartConfirmation, titleVisibility: .visible) {
            Button("重启", role: .destructive) { Task { await restart() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重启期间机器人会短暂离线。")
        }
        .sheet(isPresented: $showAccountEditor) {
            AccountEditorView()
        }
    }

    @MainActor
    private func loadVersions() async {
        guard let client = appState.apiClient else { return }
        do { versions = try await client.request(path: "/api/v1/stats/versions", authenticated: false).data ?? .object([:]) }
        catch { /* Version metadata is non-critical. */ }
    }

    @MainActor
    private func restart() async {
        guard let client = appState.apiClient else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await client.request(path: "/api/v1/system/restart", method: .post)
            appState.showToast("已发送重启指令", style: .info)
        } catch {
            appState.showToast(error.localizedDescription, style: .error)
        }
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
                Section("验证身份") {
                    SecureField("当前密码", text: $currentPassword).textContentType(.password)
                }
                Section("账号") {
                    TextField("新用户名（可留空）", text: $newUsername)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
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
