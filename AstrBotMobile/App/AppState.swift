import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppState {
    enum Theme: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
    }

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard

    var serverURLText: String
    var username: String
    var token: String?
    var authMode: AuthenticationMode
    var theme: Theme
    var isRestoringSession = true
    var toast: ToastMessage?

    init() {
        serverURLText = defaults.string(forKey: "serverURL") ?? ""
        username = defaults.string(forKey: "username") ?? ""
        authMode = AuthenticationMode(rawValue: defaults.string(forKey: "authMode") ?? "jwt") ?? .jwt
        theme = Theme(rawValue: defaults.string(forKey: "theme") ?? "system") ?? .system
        token = try? keychain.read(account: "astrbot.auth.token")
        isRestoringSession = false
    }

    var isAuthenticated: Bool {
        guard let token else { return false }
        return !serverURLText.isEmpty && !token.isEmpty
    }

    var preferredColorScheme: ColorScheme? {
        switch theme {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var apiClient: AstrBotAPIClient? {
        guard let baseURL = URL.normalizedServerURL(from: serverURLText), let token else {
            return nil
        }
        return AstrBotAPIClient(baseURL: baseURL, token: token, authenticationMode: authMode)
    }

    func saveSession(serverURL: URL, username: String, token: String, mode: AuthenticationMode) throws {
        serverURLText = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.username = username
        self.token = token
        authMode = mode
        defaults.set(serverURLText, forKey: "serverURL")
        defaults.set(username, forKey: "username")
        defaults.set(mode.rawValue, forKey: "authMode")
        try keychain.write(token, account: "astrbot.auth.token")
    }

    func updateServer(_ value: String) {
        serverURLText = value
        defaults.set(value, forKey: "serverURL")
    }

    func updateTheme(_ value: Theme) {
        theme = value
        defaults.set(value.rawValue, forKey: "theme")
    }

    func signOut() {
        token = nil
        try? keychain.delete(account: "astrbot.auth.token")
    }

    func showToast(_ title: String, style: ToastMessage.Style = .success) {
        toast = ToastMessage(title: title, style: style)
        Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            if toast?.title == title {
                toast = nil
            }
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case error
        case info
    }

    let id = UUID()
    let title: String
    let style: Style
}
