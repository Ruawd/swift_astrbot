import Testing
import Foundation
@testable import AstrBotMobile

struct AstrBotMobileTests {
    @Test func normalizesServerURL() {
        #expect(URL.normalizedServerURL(from: "bot.example.com/")?.absoluteString == "https://bot.example.com")
        #expect(URL.normalizedServerURL(from: "http://192.168.1.8:6185") != nil)
        #expect(URL.normalizedServerURL(from: "not a host") == nil)
    }

    @Test func jsonRoundTrip() throws {
        let value = try "{\"enabled\":true,\"count\":2}".parsedJSONValue()
        #expect(value["enabled"]?.stringValue == "true")
        #expect(value["count"]?.stringValue == "2")
    }

    @Test func bundledOpenAPIHasAllManagementRoutes() throws {
        let url = try #require(Bundle(for: TestBundleToken.self).url(forResource: "astrbot-openapi", withExtension: "json"))
        let document = try JSONDecoder().decode(OpenAPIDocument.self, from: Data(contentsOf: url))
        #expect(document.paths.count >= 224)
        #expect(document.endpoints.count > document.paths.count)
    }
}

private final class TestBundleToken: NSObject {}
