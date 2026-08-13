import Foundation

struct ChatSession: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    let updatedAt: String?

    init?(value: JSONValue) {
        guard let object = value.objectValue,
              let id = object["session_id"]?.stringValue else { return nil }
        self.id = id
        title = object["display_name"]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? "新对话"
        updatedAt = object["updated_at"]?.stringValue
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
        case system
    }

    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool

    init(id: UUID = UUID(), role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

struct ChatStreamEvent: Decodable, Sendable {
    let type: String?
    let data: JSONValue?
    let chainType: String?
    let streaming: Bool?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case type, data, streaming
        case chainType = "chain_type"
        case sessionID = "session_id"
    }

    var text: String {
        if let value = data?.stringValue { return value }
        for key in ["text", "content", "message"] {
            if let value = data?[key]?.stringValue { return value }
        }
        return ""
    }
}
