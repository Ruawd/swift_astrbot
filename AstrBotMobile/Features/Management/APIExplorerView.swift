import SwiftUI

struct APIExplorerView: View {
    @Environment(AppState.self) private var appState
    @State private var document: OpenAPIDocument?
    @State private var searchText = ""
    @State private var selectedMethod: HTTPMethod?
    @State private var isLoading = true
    @State private var errorMessage: String?
    private let service = OpenAPIService()

    private var endpoints: [APIEndpoint] {
        guard let document else { return [] }
        return document.endpoints.filter { endpoint in
            (selectedMethod == nil || endpoint.method == selectedMethod) &&
                (searchText.isEmpty || endpoint.summary.localizedStandardContains(searchText) ||
                    endpoint.path.localizedStandardContains(searchText) || endpoint.category.localizedStandardContains(searchText))
        }
    }

    var body: some View {
        ZStack {
            LiquidBackground()
            Group {
                if let errorMessage {
                    ContentUnavailableView("无法读取接口", systemImage: "network.slash", description: Text(errorMessage))
                } else {
                    List {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    methodFilter(nil, title: "全部")
                                    ForEach(HTTPMethod.allCases) { method in
                                        methodFilter(method, title: method.rawValue)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                        }
                        ForEach(Array(Dictionary(grouping: endpoints, by: \.category).keys).sorted(), id: \.self) { category in
                            Section(category) {
                                ForEach(endpoints.filter { $0.category == category }) { endpoint in
                                    NavigationLink(value: endpoint) {
                                        HStack(spacing: 10) {
                                            methodBadge(endpoint.method)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(endpoint.summary).font(.subheadline.weight(.semibold))
                                                Text(endpoint.path)
                                                    .font(.caption.monospaced())
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            if isLoading { LoadingOverlay(title: "正在载入 OpenAPI") }
        }
        .navigationTitle("全部接口")
        .searchable(text: $searchText, prompt: "搜索 224 个管理接口")
        .navigationDestination(for: APIEndpoint.self) { endpoint in
            EndpointRunnerView(endpoint: endpoint)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await load(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("刷新接口定义")
            }
        }
        .task { await load(force: false) }
    }

    private func methodFilter(_ method: HTTPMethod?, title: String) -> some View {
        Button {
            selectedMethod = method
        } label: {
            Text(title)
                .font(.caption.weight(.bold))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(selectedMethod == method ? .white : .primary)
                .background(selectedMethod == method ? AstrBotPalette.blue : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func methodBadge(_ method: HTTPMethod) -> some View {
        Text(method.rawValue)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(methodColor(method))
            .frame(width: 47)
            .padding(.vertical, 5)
            .background(methodColor(method).opacity(0.12), in: Capsule())
    }

    private func methodColor(_ method: HTTPMethod) -> Color {
        switch method {
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .patch: return .purple
        case .delete: return .red
        }
    }

    @MainActor
    private func load(force: Bool) async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            document = try await service.load(client: client, forceRemote: force)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct EndpointRunnerView: View {
    @Environment(AppState.self) private var appState
    let endpoint: APIEndpoint
    @State private var pathValues: [String: String] = [:]
    @State private var queryValues: [String: String] = [:]
    @State private var bodyText = "{}"
    @State private var responseText = ""
    @State private var errorMessage: String?
    @State private var isRunning = false
    @State private var showConfirmation = false

    private var pathParameters: [String] {
        let regex = try? NSRegularExpression(pattern: #"\{([^}]+)\}"#)
        let range = NSRange(endpoint.path.startIndex..., in: endpoint.path)
        return regex?.matches(in: endpoint.path, range: range).compactMap {
            guard let range = Range($0.range(at: 1), in: endpoint.path) else { return nil }
            return String(endpoint.path[range])
        } ?? []
    }

    private var queryParameters: [OpenAPIDocument.Parameter] {
        endpoint.parameters.filter { $0.location == "query" }
    }

    var body: some View {
        ZStack {
            LiquidBackground()
            Form {
                Section("接口") {
                    LabeledContent("方法", value: endpoint.method.rawValue)
                    Text(endpoint.path).font(.footnote.monospaced()).textSelection(.enabled)
                    if let scope = endpoint.requiredScope {
                        LabeledContent("所需权限", value: scope)
                    }
                    if !endpoint.sensitiveScopes.isEmpty {
                        Label("敏感权限：\(endpoint.sensitiveScopes.joined(separator: ", "))", systemImage: "lock.trianglebadge.exclamationmark")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
                if !pathParameters.isEmpty {
                    Section("路径参数") {
                        ForEach(pathParameters, id: \.self) { name in
                            TextField(name, text: Binding(
                                get: { pathValues[name, default: ""] },
                                set: { pathValues[name] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                    }
                }
                if !queryParameters.isEmpty {
                    Section("查询参数") {
                        ForEach(queryParameters, id: \.name) { parameter in
                            TextField(parameter.name + (parameter.required == true ? " *" : ""), text: Binding(
                                get: { queryValues[parameter.name, default: ""] },
                                set: { queryValues[parameter.name] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        }
                    }
                }
                if endpoint.hasRequestBody {
                    Section("JSON 请求体" + (endpoint.bodyRequired ? " *" : "")) {
                        TextEditor(text: $bodyText)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(minHeight: 180)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                if let errorMessage {
                    Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
                Section {
                    Button {
                        if endpoint.method == .delete { showConfirmation = true }
                        else { Task { await run() } }
                    } label: {
                        HStack {
                            if isRunning { ProgressView() }
                            Text("发送请求").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isRunning || !pathParameters.allSatisfy { !(pathValues[$0] ?? "").isEmpty })
                }
                if !responseText.isEmpty {
                    Section("响应") {
                        Text(responseText)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(endpoint.summary)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("确认执行删除操作？", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await run() } }
            Button("取消", role: .cancel) {}
        }
    }

    @MainActor
    private func run() async {
        guard let client = appState.apiClient else { return }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            var path = endpoint.path
            for (name, value) in pathValues {
                path = path.replacingOccurrences(of: "{\(name)}", with: value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value)
            }
            let query = queryValues.compactMap { name, value in
                value.isEmpty ? nil : URLQueryItem(name: name, value: value)
            }
            let body = endpoint.hasRequestBody ? try bodyText.parsedJSONValue() : nil
            let response = try await client.request(path: path, method: endpoint.method, query: query, body: body)
            responseText = (response.data ?? .null).prettyPrinted
            appState.showToast("请求执行成功")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RawJSONActionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let title: String
    let path: String
    let method: HTTPMethod
    let onSuccess: (() -> Void)?
    @State private var bodyText: String
    @State private var responseText = ""
    @State private var errorMessage: String?
    @State private var isRunning = false

    init(title: String, path: String, method: HTTPMethod, initialBody: String = "{}", onSuccess: (() -> Void)? = nil) {
        self.title = title
        self.path = path
        self.method = method
        self.onSuccess = onSuccess
        _bodyText = State(initialValue: initialBody)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("\(method.rawValue) \(path)") {
                    TextEditor(text: $bodyText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 240)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
                if !responseText.isEmpty {
                    Section("响应") { Text(responseText).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
                }
                Section {
                    Button("执行") { Task { await run() } }
                        .frame(maxWidth: .infinity)
                        .disabled(isRunning)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    @MainActor
    private func run() async {
        guard let client = appState.apiClient else { return }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }
        do {
            let body = method.hasRequestBody ? try bodyText.parsedJSONValue() : nil
            let response = try await client.request(path: path, method: method, body: body)
            responseText = (response.data ?? .null).prettyPrinted
            appState.showToast("操作成功")
            onSuccess?()
        } catch { errorMessage = error.localizedDescription }
    }
}
