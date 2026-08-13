import Foundation

struct LogEntry: Identifiable, Codable, Hashable, Sendable {
    let level: String
    let time: Double
    let data: String
    let category: String?
    // SSE event ids are transport metadata and are not part of AstrBot's
    // JSON log payload.  A default keeps Codable synthesis valid while the
    // stream client can attach the id after decoding.
    var eventID: String? = nil

    var id: String {
        return eventID ?? "\(time)-\(level)-\(data.hashValue)"
    }

    var normalizedLevel: String {
        switch level.uppercased() {
        case "DEBG": return "DEBUG"
        case "WARN": return "WARNING"
        case "ERRO": return "ERROR"
        case "CRIT": return "CRITICAL"
        default: return level.uppercased()
        }
    }

    var cleanedMessage: String {
        return data.replacingOccurrences(of: "\\x1B\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    func with(eventID: String?) -> LogEntry {
        var copy = self
        copy.eventID = eventID
        return copy
    }

    init?(value: JSONValue) {
        guard let object = value.objectValue,
              let level = object["level"]?.stringValue,
              let data = object["data"]?.stringValue else { return nil }
        self.level = level
        if case let .number(value) = object["time"] { time = value }
        else { time = Double(object["time"]?.stringValue ?? "") ?? Date().timeIntervalSince1970 }
        self.data = data
        category = object["category"]?.stringValue
        eventID = nil
    }

    private enum CodingKeys: String, CodingKey {
        case level, time, data, category
    }
}
