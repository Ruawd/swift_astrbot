import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var totpCode = ""
    @State private var apiKey = ""
    @State private var authMode: AuthenticationMode = .jwt
    @State private var trustDevice = true
    @State private var showTOTP = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case server, username, password, totp, apiKey
    }

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            LiquidBackground()
            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 32)
                    VStack(spacing: 14) {
                        AstrBotLogo(size: 82)
                        Text("AstrBot Mobile")
                            .font(.largeTitle.bold())
                        Text("原生、安全、完整的机器人管理端")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 18) {
                        Picker("认证方式", selection: $authMode) {
                            ForEach(AuthenticationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        labeledField("服务器地址", icon: "server.rack") {
                            TextField("https://bot.example.com", text: $serverURL)
                                .textContentType(.URL)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .server)
                                .submitLabel(.next)
                                .onSubmit { focusedField = authMode == .jwt ? .username : .apiKey }
                        }

                        if authMode == .jwt {
                            labeledField("用户名", icon: "person") {
                                TextField("admin", text: $username)
                                    .textContentType(.username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .username)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .password }
                            }
                            labeledField("密码", icon: "lock") {
                                SecureField("输入密码", text: $password)
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    .submitLabel(showTOTP ? .next : .go)
                                    .onSubmit {
                                        if showTOTP { focusedField = .totp } else { Task { await authenticate() } }
                                    }
                            }
                            if showTOTP {
                                labeledField("两步验证码", icon: "number.square") {
                                    TextField("6 位验证码", text: $totpCode)
                                        .keyboardType(.numberPad)
                                        .textContentType(.oneTimeCode)
                                        .focused($focusedField, equals: .totp)
                                }
                                Toggle("信任这台设备", isOn: $trustDevice)
                            }
                        } else {
                            labeledField("API Key", icon: "key") {
                                SecureField("粘贴拥有管理权限的 Key", text: $apiKey)
                                    .textContentType(.password)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .apiKey)
                                    .submitLabel(.go)
                                    .onSubmit { Task { await authenticate() } }
                            }
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("登录错误：\(errorMessage)")
                        }

                        Button {
                            Task { await authenticate() }
                        } label: {
                            HStack {
                                if isLoading { ProgressView().tint(.white) }
                                Text(authMode == .jwt ? "登录" : "连接服务器")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AstrBotPalette.blue)
                        .disabled(isLoading || !canSubmit)
                    }
                    .padding(20)
                    .glassSurface(radius: 28)

                    Text("凭据仅保存在本机钥匙串中。建议通过 HTTPS 或可信 VPN 连接 AstrBot。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            if isLoading {
                Color.black.opacity(0.001).ignoresSafeArea()
            }
        }
        .onAppear {
            serverURL = appState.serverURLText
            username = appState.username
            authMode = appState.authMode
        }
    }

    private var canSubmit: Bool {
        guard URL.normalizedServerURL(from: serverURL) != nil else { return false }
        if authMode == .apiKey { return !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !username.isEmpty && !password.isEmpty
    }

    private func labeledField<Content: View>(_ label: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @MainActor
    private func authenticate() async {
        guard canSubmit, let url = URL.normalizedServerURL(from: serverURL) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if authMode == .apiKey {
                let client = AstrBotAPIClient(baseURL: url, token: apiKey, authenticationMode: .apiKey)
                _ = try await client.request(path: "/api/v1/stats/versions")
                try appState.saveSession(serverURL: url, username: "API Key", token: apiKey, mode: .apiKey)
            } else {
                let client = AstrBotAPIClient(baseURL: url)
                let result = try await client.login(
                    username: username,
                    password: password,
                    code: totpCode.isEmpty ? nil : totpCode,
                    trustDevice: trustDevice
                )
                try appState.saveSession(serverURL: url, username: result.username, token: result.token, mode: .jwt)
            }
        } catch let error as APIError {
            if case let .unauthorized(message) = error,
               message.localizedCaseInsensitiveContains("totp") || message.contains("验证码") {
                showTOTP = true
                focusedField = .totp
            }
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
