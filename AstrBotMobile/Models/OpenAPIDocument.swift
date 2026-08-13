import Foundation

struct OpenAPIDocument: Decodable, Sendable {
    struct Info: Decodable, Sendable {
        let title: String
        let version: String
    }

    struct Operation: Decodable, Sendable {
        let tags: [String]?
        let summary: String?
        let description: String?
        let operationId: String?
        let parameters: [Parameter]?
        let requestBody: RequestBody?
        let requiredScope: String?
        let sensitiveScopes: [String]?

        enum CodingKeys: String, CodingKey {
            case tags, summary, description, operationId, parameters, requestBody
            case requiredScope = "x-astrbot-scope"
            case sensitiveScopes = "x-astrbot-sensitive-scopes"
        }
    }

    struct Parameter: Decodable, Sendable, Hashable {
        let name: String
        let location: String
        let required: Bool?
        let schema: JSONValue?

        enum CodingKeys: String, CodingKey {
            case name, required, schema
            case location = "in"
        }
    }

    struct RequestBody: Decodable, Sendable {
        let required: Bool?
        let content: [String: MediaType]?
    }

    struct MediaType: Decodable, Sendable {
        let schema: JSONValue?
    }

    let openapi: String
    let info: Info
    let paths: [String: [String: Operation]]

    var endpoints: [APIEndpoint] {
        paths.flatMap { path, operations in
            operations.compactMap { methodName, operation in
                guard let method = HTTPMethod(rawValue: methodName.uppercased()) else { return nil }
                return APIEndpoint(path: path, method: method, operation: operation)
            }
        }
        .sorted { lhs, rhs in
            if lhs.category == rhs.category { return lhs.path == rhs.path ? lhs.method.rawValue < rhs.method.rawValue : lhs.path < rhs.path }
            return lhs.category < rhs.category
        }
    }
}

struct APIEndpoint: Identifiable, Hashable, Sendable {
    let path: String
    let method: HTTPMethod
    let category: String
    let summary: String
    let details: String?
    let operationID: String?
    let parameters: [OpenAPIDocument.Parameter]
    let hasRequestBody: Bool
    let bodyRequired: Bool
    let requiredScope: String?
    let sensitiveScopes: [String]

    var id: String { return "\(method.rawValue):\(path)" }

    init(path: String, method: HTTPMethod, operation: OpenAPIDocument.Operation) {
        self.path = path
        self.method = method
        category = operation.tags?.first ?? "Other"
        summary = operation.summary ?? path
        details = operation.description
        operationID = operation.operationId
        parameters = operation.parameters ?? []
        hasRequestBody = operation.requestBody != nil
        bodyRequired = operation.requestBody?.required ?? false
        requiredScope = operation.requiredScope
        sensitiveScopes = operation.sensitiveScopes ?? []
    }

    static func == (lhs: APIEndpoint, rhs: APIEndpoint) -> Bool { return lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
