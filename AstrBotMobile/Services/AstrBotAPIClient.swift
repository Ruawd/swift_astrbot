import Foundation

enum AuthenticationMode: String, Codable, CaseIterable, Identifiable {
    case jwt
    case apiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jwt: return "账号登录"
        case .apiKey: return "API Key"
        }
    }
}

enum HTTPMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    var id: String { rawValue }

    var hasRequestBody: Bool {
        return self != .get && self != .delete
    }
}

struct APIEnvelope: Decodable, Sendable {
    let status: String?
    let message: String?
    let data: JSONValue?
}

struct LoginResult: Sendable {
    let username: String
    let token: String
}

struct AstrBotAPIClient: Sendable {
    let baseURL: URL
    let token: String?
    let authenticationMode: AuthenticationMode
    let session: URLSession

    private static let sessionLock = NSLock()
    nonisolated(unsafe) private static var sessions: [String: URLSession] = [:]

    init(
        baseURL: URL,
        token: String? = nil,
        authenticationMode: AuthenticationMode = .jwt,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.token = token
        self.authenticationMode = authenticationMode
        self.session = session ?? AstrBotAPIClient.session(for: baseURL)
    }

    private static func session(for baseURL: URL) -> URLSession {
        let key = baseURL.absoluteString
        sessionLock.lock()
        defer { sessionLock.unlock() }
        if let session = sessions[key] { return session }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadRevalidatingCacheData
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCredentialStorage = .shared
        let session = URLSession(configuration: configuration)
        sessions[key] = session
        return session
    }

    func login(username: String, password: String, code: String?, trustDevice: Bool) async throws -> LoginResult {
        var payload: [String: JSONValue] = [
            "username": .string(username),
            "password": .string(password),
            "trust_device_flag": .bool(trustDevice),
        ]
        if let code, !code.isEmpty { payload["code"] = .string(code) }
        let response = try await request(
            path: "/api/v1/auth/login",
            method: .post,
            body: .object(payload),
            authenticated: false
        )
        guard let data = response.data?.objectValue,
              let token = data["token"]?.stringValue,
              !token.isEmpty else {
            throw APIError.server(response.message ?? "登录响应中没有 Token")
        }
        return LoginResult(username: data["username"]?.stringValue ?? username, token: token)
    }

    func setupStatus() async throws -> JSONValue {
        try await request(path: "/api/v1/auth/setup-status", authenticated: false).data ?? .null
    }

    func request(
        path: String,
        method: HTTPMethod = .get,
        query: [URLQueryItem] = [],
        body: JSONValue? = nil,
        authenticated: Bool = true
    ) async throws -> APIEnvelope {
        guard var components = URLComponents(url: baseURL.appendingAPIPath(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN", forHTTPHeaderField: "Accept-Language")
        if authenticated, let token, !token.isEmpty {
            switch authenticationMode {
            case .jwt:
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            case .apiKey:
                request.setValue("ApiKey \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let envelope = try? JSONDecoder().decode(APIEnvelope.self, from: data)
        if !(200 ... 299).contains(http.statusCode) {
            if http.statusCode == 401 { throw APIError.unauthorized(envelope?.message ?? "登录已过期") }
            throw APIError.http(status: http.statusCode, message: envelope?.message ?? String(data: data, encoding: .utf8))
        }
        if let envelope {
            if envelope.status == "error" { throw APIError.server(envelope.message ?? "服务器返回错误") }
            return envelope
        }
        if data.isEmpty { return APIEnvelope(status: "ok", message: nil, data: .null) }
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return APIEnvelope(status: "ok", message: nil, data: value)
    }

    func download(path: String, query: [URLQueryItem] = []) async throws -> (Data, URLResponse) {
        guard var components = URLComponents(url: baseURL.appendingAPIPath(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        if let token {
            request.setValue(authenticationMode == .jwt ? "Bearer \(token)" : "ApiKey \(token)", forHTTPHeaderField: "Authorization")
        }
        return try await session.data(for: request)
    }

    func streamChat(message: String, sessionID: String) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    let url = baseURL.appendingAPIPath("/api/v1/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 300
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token {
                        request.setValue(
                            authenticationMode == .jwt ? "Bearer \(token)" : "ApiKey \(token)",
                            forHTTPHeaderField: "Authorization"
                        )
                    }
                    request.httpBody = try JSONEncoder().encode(
                        JSONValue.object([
                            "message": .string(message),
                            "session_id": .string(sessionID),
                            "enable_streaming": .bool(true),
                        ])
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw APIError.http(status: http.statusCode, message: nil)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !payload.isEmpty, payload != "[DONE]", let data = payload.data(using: .utf8) else { continue }
                        continuation.yield(try JSONDecoder().decode(ChatStreamEvent.self, from: data))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    func streamLogs(lastEventID: String? = nil) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    var request = URLRequest(url: baseURL.appendingAPIPath("/api/v1/logs/live"))
                    request.timeoutInterval = 60 * 60
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                    if let lastEventID { request.setValue(lastEventID, forHTTPHeaderField: "Last-Event-ID") }
                    if let token {
                        request.setValue(
                            authenticationMode == .jwt ? "Bearer \(token)" : "ApiKey \(token)",
                            forHTTPHeaderField: "Authorization"
                        )
                    }
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                    guard (200 ... 299).contains(http.statusCode) else {
                        throw APIError.http(status: http.statusCode, message: nil)
                    }
                    var eventID: String?
                    for try await line in bytes.lines {
                        if line.hasPrefix("id:") {
                            eventID = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8) else { continue }
                        let entry = try JSONDecoder().decode(LogEntry.self, from: data)
                        continuation.yield(entry.with(eventID: eventID))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case invalidJSON
    case unauthorized(String)
    case http(status: Int, message: String?)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .invalidResponse: return "服务器响应无效"
        case .invalidJSON: return "JSON 格式不正确"
        case let .unauthorized(message): return message
        case let .http(status, message): return message.flatMap { $0.isEmpty ? nil : $0 } ?? "HTTP 错误 \(status)"
        case let .server(message): return message
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL), (.invalidResponse, .invalidResponse), (.invalidJSON, .invalidJSON):
            return true
        case let (.unauthorized(left), .unauthorized(right)), let (.server(left), .server(right)):
            return left == right
        case let (.http(leftStatus, leftMessage), .http(rightStatus, rightMessage)):
            return leftStatus == rightStatus && leftMessage == rightMessage
        default:
            return false
        }
    }
}
