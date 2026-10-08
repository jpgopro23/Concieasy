import XCTest

final class ConcieasyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNativeSignInOffersExistingAccountCredentials() {
        let app = XCUIApplication()
        app.launch()
        let signIn = app.buttons["Sign in"].firstMatch
        if !signIn.waitForExistence(timeout: 5) {
            app.buttons["Account and workspace actions"].tap()
        }
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        signIn.tap()
        XCTAssertTrue(app.staticTexts["Welcome back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["signInUsername"].exists)
        XCTAssertTrue(app.secureTextFields["signInPassword"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.secureTextFields["signInPassword"].exists)
    }
}
