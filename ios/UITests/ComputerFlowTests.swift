import XCTest

final class ComputerFlowTests: XCTestCase {
    func testSaveReopenAndConnectWithOneTap() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["addComputer"].tap()
        let name = app.textFields["computerName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let address = app.textFields["addressField"]
        address.tap(); address.typeText("https://gaming.example.com")
        let token = app.secureTextFields["tokenField"]
        token.tap(); token.typeText("ui-test-only")
        app.buttons["saveComputer"].tap()
        let connect = app.buttons["Conectar a Meu PC"]
        XCTAssertTrue(connect.waitForExistence(timeout: 8), "Saved card must appear after Keychain write")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Saved-computer-library"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Conectar a Meu PC"].waitForExistence(timeout: 8))
        app.buttons["Conectar a Meu PC"].tap()
        XCTAssertTrue(app.buttons["Voltar aos computadores"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.secureTextFields["tokenField"].exists)
        app.buttons["Voltar aos computadores"].tap()
        XCTAssertTrue(app.buttons["Conectar a Meu PC"].waitForExistence(timeout: 5))
    }
}
