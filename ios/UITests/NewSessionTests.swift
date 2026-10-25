import XCTest

/// 開新 session：選帳號、填第一句話、選資料夾、按開始（B2）
final class NewSessionTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCreateWithFirstPrompt() throws {
        let app = try launchApp()
        let plus = app.buttons["開新 session"]
        XCTAssertTrue(plus.waitForExistence(timeout: 15))
        plus.tap()
        let start = app.buttons["開始"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(start.isEnabled, "還沒選資料夾就能按開始")
        app.buttons["peter"].tap()
        // 先選資料夾再打字：鍵盤起來之後下面的資料夾會被蓋住
        let notes = app.staticTexts["notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10))
        notes.tap()
        XCTAssertTrue(start.isEnabled, "選了資料夾還不能按開始")
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("跑測試")
        shot(app, "picked")
        start.tap()
        let opened = NSPredicate(format: "exists == false")
        expectation(for: opened, evaluatedWith: start)
        waitForExpectations(timeout: 10)
        let cmd = try FakeBackend.log().first { $0.op == "new_tab" }?.command ?? ""
        XCTAssertTrue(cmd.contains("/Projects/notes"), "沒有 cd 到選的資料夾：\(cmd)")
        XCTAssertTrue(cmd.contains("CLAUDE_CONFIG_DIR="), "沒有用選的帳號：\(cmd)")
        XCTAssertTrue(cmd.contains("跑測試"), "第一句話沒帶到：\(cmd)")
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.waitForExistence(timeout: 10))
        shot(app, "opened")
    }
}
