import SwiftUI

struct ChatView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [ChatSession] = []
    @State private var selectedSessionID: String?
    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var streamingTask: Task<Void, Never>?
    @FocusState private var composerFocused: Bool

    var body: some View {
        ZStack {
            LiquidBackground()
            VStack(spacing: 0) {
                if messages.isEmpty && !isLoading {
                    EmptyStateView(
                        icon: "sparkles",
                        title: "开始与 AstrBot 对话",
                        description: "支持 AstrBot WebChat 会话与流式回复"
                    )
                } else {
                    messageList
                }
                composer
            }
            if isLoading { LoadingOverlay(title: "正在加载会话") }
        }
        .navigationTitle(currentSessionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { sessionMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await createSession() } } label: { Image(systemName: "square.and.pencil") }
                    .accessibilityLabel("新建对话")
            }
        }
        .task { await loadSessions() }
        .onDisappear { streamingTask?.cancel() }
    }

    private var currentSessionTitle: String {
        sessions.first(where: { $0.id == selectedSessionID })?.title ?? "聊天"
    }

    private var sessionMenu: some View {
        Menu {
            ForEach(sessions) { session in
                Button {
                    selectedSessionID = session.id
                    Task { await loadSession(session.id) }
                } label: {
                    Label(session.title, systemImage: session.id == selectedSessionID ? "checkmark.circle.fill" : "bubble.left")
                }
            }
            Divider()
            Button { Task { await createSession() } } label: {
                Label("新建对话", systemImage: "plus")
            }
        } label: {
            Image(systemName: "sidebar.left")
        }
        .accessibilityLabel("会话列表")
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(12)
                            .glassSurface(radius: 14)
                    }
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                let value = messages
                guard let id = value.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("发送消息…", text: $draft, axis: .vertical)
                .lineLimit(1 ... 6)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("消息内容")
            Button {
                if isSending { streamingTask?.cancel(); isSending = false }
                else { send() }
            } label: {
                Image(systemName: isSending ? "stop.fill" : "arrow.up")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(isSending ? Color.red : AstrBotPalette.blue, in: Circle())
            }
            .disabled(!isSending && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(isSending ? "停止生成" : "发送")
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .glassSurface(radius: 24)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    @MainActor
    private func loadSessions() async {
        guard let client = appState.apiClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.request(path: "/api/v1/chat/sessions")
            let raw = response.data?.arrayValue ?? response.data?["items"]?.arrayValue ?? []
            sessions = raw.compactMap(ChatSession.init(value:))
            if let first = sessions.first {
                selectedSessionID = selectedSessionID ?? first.id
                await loadSession(selectedSessionID ?? first.id)
            } else {
                await createSession()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func createSession() async {
        guard let client = appState.apiClient else { return }
        do {
            let response = try await client.request(
                path: "/api/v1/chat/sessions/new",
                query: [URLQueryItem(name: "platform_id", value: "webchat")]
            )
            guard let id = response.data?["session_id"]?.stringValue else { throw APIError.invalidResponse }
            let session = ChatSession(value: .object([
                "session_id": .string(id),
                "display_name": .string("新对话"),
            ]))!
            sessions.insert(session, at: 0)
            selectedSessionID = id
            messages = []
            composerFocused = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func loadSession(_ id: String) async {
        guard let client = appState.apiClient else { return }
        errorMessage = nil
        do {
            let response = try await client.request(path: "/api/v1/chat/sessions/\(id)")
            let history = response.data?["history"]?.arrayValue
                ?? response.data?["messages"]?.arrayValue
                ?? response.data?["history_list"]?.arrayValue
                ?? []
            messages = history.compactMap(Self.parseHistoryMessage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func parseHistoryMessage(_ value: JSONValue) -> ChatMessage? {
        guard let object = value.objectValue else { return nil }
        let content = object["content"]?.objectValue ?? object
        let type = content["type"]?.stringValue ?? object["role"]?.stringValue ?? "bot"
        let parts = content["message"]?.arrayValue ?? []
        let text = parts.compactMap { part in
            if let string = part.stringValue { return string }
            return part["text"]?.stringValue ?? part["content"]?.stringValue
        }.joined()
        guard !text.isEmpty else { return nil }
        return ChatMessage(role: type == "user" ? .user : .assistant, text: text)
    }

    private func send() {
        guard let client = appState.apiClient,
              let sessionID = selectedSessionID else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: content))
        let botMessageID = UUID()
        messages.append(ChatMessage(id: botMessageID, role: .assistant, text: "", isStreaming: true))
        isSending = true
        streamingTask = Task {
            do {
                for try await event in client.streamChat(message: content, sessionID: sessionID) {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        guard let index = messages.firstIndex(where: { $0.id == botMessageID }) else { return }
                        if event.type == "plain", event.chainType != "reasoning" {
                            messages[index].text += event.text
                        } else if ["complete", "break"].contains(event.type ?? ""), messages[index].text.isEmpty {
                            messages[index].text = event.text
                        } else if event.type == "error" {
                            messages[index].text += "\n\n\(event.text)"
                        }
                        if event.type == "end" { messages[index].isStreaming = false }
                    }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
            await MainActor.run {
                if let index = messages.firstIndex(where: { $0.id == botMessageID }) {
                    messages[index].isStreaming = false
                    if messages[index].text.isEmpty { messages[index].text = "未收到文本回复" }
                }
                isSending = false
            }
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user { Spacer(minLength: 46) }
            if message.role == .assistant {
                AstrBotLogo(size: 30)
            }
            VStack(alignment: .leading, spacing: 6) {
                if message.text.isEmpty && message.isStreaming {
                    ProgressView().controlSize(.small).padding(.horizontal, 6)
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                        .font(.body)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(message.role == .user ? Color.white : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(message.role == .user ? AnyShapeStyle(AstrBotPalette.blue.gradient) : AnyShapeStyle(.thinMaterial))
            }
            if message.role != .user { Spacer(minLength: 46) }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.role == .user ? "你" : "AstrBot")
    }
}
