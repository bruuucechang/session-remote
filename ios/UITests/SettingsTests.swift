import XCTest

/// 設定頁與第一次配對（B2）
final class SettingsTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSettingsPage() throws {
        let app = try launchApp()
        let gear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "設定")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()
        XCTAssertTrue(app.switches.firstMatch.waitForExistence(timeout: 10), "沒讀到筆電上的推播設定")
        shot(app, "settings")
        app.buttons["完成"].tap()
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
    }

    func testFirstRunWrongThenRightToken() throws {
        let app = try launchApp(["SR_FIRSTRUN": "1"])
        let token = app.secureTextFields.firstMatch
        XCTAssertTrue(token.waitForExistence(timeout: 10), "第一次打開沒有配對頁")
        token.tap()
        token.typeText("wrong")
        app.buttons["儲存並連線"].tap()
        XCTAssertTrue(app.any("通行碼").waitForExistence(timeout: 15))
        XCTAssertTrue(app.any("pair.py").exists, "失敗時沒講怎麼辦")
        XCTAssertTrue(app.secureTextFields.firstMatch.exists, "通行碼錯了卻離開配對頁")
        shot(app, "pair-failed")
        let field = app.secureTextFields.firstMatch
        // 欄位靠右對齊：點正中間游標會落在最前面，刪除鍵刪不到字；點最右邊
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + FakeBackend.token)
        let typed = (field.value as? String) ?? ""
        app.buttons["儲存並連線"].tap()
        XCTAssertTrue(app.staticTexts["hello"].waitForExistence(timeout: 15), "通行碼對了沒進列表（欄位裡有 \(typed.count) 個字）")
    }
}
