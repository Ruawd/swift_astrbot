import Foundation

actor OpenAPIService {
    private var cached: OpenAPIDocument?

    func load(client: AstrBotAPIClient, forceRemote: Bool = false) async throws -> OpenAPIDocument {
        if let cached, !forceRemote { return cached }
        if forceRemote || cached == nil {
            do {
                let (data, response) = try await client.download(path: "/api/v1/openapi.json")
                if let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) {
                    let document = try JSONDecoder().decode(OpenAPIDocument.self, from: data)
                    cached = document
                    return document
                }
            } catch where forceRemote {
                throw error
            } catch {
                // Fall back to the bundled schema when the server is offline or older.
            }
        }
        guard let url = Bundle.main.url(forResource: "astrbot-openapi", withExtension: "json") else {
            throw APIError.invalidResponse
        }
        let document = try JSONDecoder().decode(OpenAPIDocument.self, from: Data(contentsOf: url))
        cached = document
        return document
    }
}
