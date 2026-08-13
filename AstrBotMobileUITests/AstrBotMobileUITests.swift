import XCTest

final class AstrBotMobileUITests: XCTestCase {
    func testLoginScreenLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["AstrBot Mobile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["登录"].exists)
    }
}
