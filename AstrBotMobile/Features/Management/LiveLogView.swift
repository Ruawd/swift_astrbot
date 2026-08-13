import SwiftUI

struct LiveLogView: View {
    @Environment(AppState.self) private var appState
    @State private var entries: [LogEntry] = []
    @State private var selectedLevels = Set(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"])
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var hideUserChat = false
    @State private var isConnected = false
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    private var filteredEntries: [LogEntry] {
        entries.filter { entry in
            selectedLevels.contains(entry.normalizedLevel) &&
                (!hideUserChat || entry.category != "user_chat") &&
                (searchText.isEmpty || entry.cleanedMessage.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.075).ignoresSafeArea()
            VStack(spacing: 0) {
                controls
                Divider().overlay(.white.opacity(0.15))
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        isConnected ? "等待新日志" : "正在连接日志流",
                        systemImage: "terminal",
                        description: Text(errorMessage ?? "历史日志和后续日志会实时显示在这里")
                    )
                    .foregroundStyle(.white)
                } else {
                    logList
                }
            }
        }
        .navigationTitle("控制台")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "搜索日志")
        .task { await start() }
        .onDisappear { streamTask?.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(isConnected ? .green : .orange).frame(width: 8, height: 8)
                    Text(isConnected ? "实时连接" : "连接中")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Menu {
                    Toggle("自动滚动", isOn: $autoScroll)
                    Toggle("隐藏用户聊天", isOn: $hideUserChat)
                    Divider()
                    Button("清空当前屏幕", role: .destructive) { entries.removeAll() }
                    Button("重新连接") { Task { await start() } }
                } label: {
                    Label("显示", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                }
                .tint(.white)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], id: \.self) { level in
                        Button {
                            if selectedLevels.contains(level) { selectedLevels.remove(level) }
                            else { selectedLevels.insert(level) }
                        } label: {
                            Text(level)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedLevels.contains(level) ? Color.black : levelColor(level))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedLevels.contains(level) ? levelColor(level) : Color.clear, in: Capsule())
                                .overlay { Capsule().stroke(levelColor(level).opacity(0.8)) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        LogRow(entry: entry, tint: levelColor(entry.normalizedLevel))
                            .id(entry.id)
                        Divider().overlay(.white.opacity(0.06))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .onChange(of: filteredEntries.count) { _, _ in
                guard autoScroll, let last = filteredEntries.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level {
        case "DEBUG": return Color(white: 0.72)
        case "INFO": return Color(red: 0.4, green: 0.72, blue: 1)
        case "WARNING": return .yellow
        case "ERROR": return Color(red: 1, green: 0.35, blue: 0.35)
        case "CRITICAL": return Color(red: 0.9, green: 0.45, blue: 1)
        default: return .white
        }
    }

    @MainActor
    private func start() async {
        guard let client = appState.apiClient else { return }
        streamTask?.cancel()
        isConnected = false
        errorMessage = nil
        do {
            let response = try await client.request(path: "/api/v1/logs/history")
            entries = (response.data?["logs"]?.arrayValue ?? []).compactMap(LogEntry.init(value:))
            if entries.count > 500 { entries.removeFirst(entries.count - 500) }
        } catch {
            errorMessage = "历史日志读取失败：\(error.localizedDescription)"
        }
        streamTask = Task {
            var retry = 0
            while !Task.isCancelled {
                do {
                    let lastID = await MainActor.run { entries.last?.eventID ?? entries.last.map { String($0.time) } }
                    await MainActor.run { isConnected = true; errorMessage = nil }
                    for try await entry in client.streamLogs(lastEventID: lastID) {
                        guard !Task.isCancelled else { break }
                        await MainActor.run {
                            if !entries.contains(where: { $0.time == entry.time && $0.data == entry.data && $0.level == entry.level }) {
                                entries.append(entry)
                                if entries.count > 1000 { entries.removeFirst(entries.count - 1000) }
                            }
                        }
                    }
                    retry = 0
                } catch {
                    await MainActor.run {
                        isConnected = false
                        errorMessage = "日志流断开，正在重连：\(error.localizedDescription)"
                    }
                    retry += 1
                    let delay = min(pow(2.0, Double(retry)), 30.0)
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(Date(timeIntervalSince1970: entry.time).formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.white.opacity(0.45))
                Text(entry.normalizedLevel)
                    .foregroundStyle(tint)
                    .fontWeight(.bold)
                if let category = entry.category, !category.isEmpty {
                    Text(category).foregroundStyle(.white.opacity(0.35))
                }
            }
            .font(.system(size: 10, design: .monospaced))
            Text(entry.cleanedMessage)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
