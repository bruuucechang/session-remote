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
        // 用資料夾按鈕找：staticTexts 會先找到後面列表「待命」收合標頭裡的 notes（點不到）
        let notes = app.buttons["notes"].firstMatch
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

    func testLaneFoldersHiddenUnlessSearching() throws {
        // *-lanes 是並行 session 的 worktree 分身，平常不列；搜尋才找得到（使用者裁示 2026-10-26）
        let app = try launchApp()
        app.buttons["開新 session"].tap()
        XCTAssertTrue(app.staticTexts["notes"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["shop-lanes"].exists, "分身資料夾還列在清單裡")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("lanes")
        XCTAssertTrue(app.staticTexts["shop-lanes"].waitForExistence(timeout: 5), "搜尋找不到分身資料夾")
    }
}
