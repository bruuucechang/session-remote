import XCTest

/// 地基：能連上假資料後端、列表照狀態排、點進一個 session 看得到對話。
final class SmokeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testListAndOpenSession() throws {
        let app = try launchApp()
        XCTAssertTrue(app.staticTexts["hello"].waitForExistence(timeout: 15), "列表沒出現假資料的 session")
        XCTAssertTrue(app.staticTexts["ledger"].exists)
        shot(app, "list")

        app.staticTexts["ledger"].tap()
        let last = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "兩個紅的都修好了")).firstMatch
        XCTAssertTrue(last.waitForExistence(timeout: 10), "點進去看不到最後一則訊息")
        shot(app, "detail")
    }
}
