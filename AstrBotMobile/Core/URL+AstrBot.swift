import Foundation

extension URL {
    static func normalizedServerURL(from text: String) -> URL? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host,
              !host.isEmpty,
              !host.contains(" ") else {
            return nil
        }
        var path = components.path
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        if path == "/" { path = "" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    func appendingAPIPath(_ path: String) -> URL {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return appendingPathComponent(cleanPath)
    }
}
