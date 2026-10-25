import XCTest

/// 對話頁：送字、中斷、關分頁、搜尋、工具、空狀態（B3）
final class DetailTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// 從列表點進某個 session
    private func open(_ app: XCUIApplication, _ name: String) {
        let row = app.staticTexts[name]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "列表沒有 \(name)")
        row.tap()
        // 列表剛好在重新整理時，第一下會被吃掉：沒進去就再點一次
        if !app.textViews.firstMatch.waitForExistence(timeout: 5), !app.navigationBars.staticTexts[name].exists, row.exists { row.tap() }
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 10), "對話頁沒有輸入框")
    }

    func testSendReply() throws {
        let app = try launchApp()
        open(app, "ledger")
        let send = app.buttons["送出"]
        XCTAssertFalse(send.isEnabled, "輸入框空著卻能按送出")
        let box = app.textViews.firstMatch
        box.tap()
        box.typeText("再跑一次")
        XCTAssertTrue(send.isEnabled, "打了字還不能送")
        shot(app, "typed")
        send.tap()
        let sent = NSPredicate { _, _ in
            (try? FakeBackend.log().contains { $0.op == "write" && $0.text == "再跑一次" }) ?? false
        }
        expectation(for: sent, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        let cleared = NSPredicate(format: "value == ''")
        expectation(for: cleared, evaluatedWith: box)
        waitForExpectations(timeout: 5)
    }

    func testReplyErrorShowsAboveComposer() throws {
        // ledger 在這個情境送字會失敗；錯誤字只有送字這一步會產生（重新載入不會）
        let app = try launchApp(scenario: "write-fails")
        open(app, "ledger")
        let box = app.textViews.firstMatch
        box.tap()
        box.typeText("還在嗎")
        app.buttons["送出"].tap()
        let err = app.any("送字失敗")
        XCTAssertTrue(err.waitForExistence(timeout: 10), "送不出去沒有錯誤訊息")
        XCTAssertLessThanOrEqual(err.frame.maxY, box.frame.minY + 1, "錯誤沒放在輸入框上方")
        shot(app, "reply-error")
    }

    func testInterruptWorking() throws {
        let app = try launchApp()
        open(app, "atlas")
        XCTAssertTrue(app.any("Bash：跑測試").waitForExistence(timeout: 10), "工作中沒顯示在做什麼")
        app.buttons["中斷"].tap()
        let sent = NSPredicate { _, _ in
            (try? FakeBackend.log().contains { $0.op == "ascii" && $0.code == 27 && $0.id == "FAKE-WORK" }) ?? false
        }
        expectation(for: sent, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        shot(app, "interrupted")
    }

    func testCloseFromDetail() throws {
        let app = try launchApp()
        open(app, "ledger")
        app.buttons["更多操作"].tap()
        app.buttons["關掉這個 session"].tap()
        app.buttons["關掉"].tap()
        let back = NSPredicate(format: "exists == false")
        expectation(for: back, evaluatedWith: app.staticTexts["ledger"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.staticTexts["hello"].exists, "關掉之後沒回到列表")
        XCTAssertTrue(try FakeBackend.log().contains { $0.op == "close" && $0.id == "FAKE-DONE" })
    }

    func testSearchConversation() throws {
        let app = try launchApp()
        open(app, "ledger")
        app.buttons["搜尋對話"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("四捨五入")
        // 要找搜尋結果那一格：同一段字在後面的對話裡也有
        let hit = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "利息沒有")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "搜尋沒找到")
        shot(app, "search")
        hit.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.searchFields.firstMatch)
        waitForExpectations(timeout: 5)
    }

    func testCollapsedToolGroupNamesEveryTool() throws {
        let app = try launchApp()
        open(app, "ledger")
        // ledger 的對話是 Bash 再 Edit：收起來時也要看得出有 Bash
        let toggle = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "工具")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.label.contains("Bash"), "收起的工具群組看不出有 Bash：\(toggle.label)")
        shot(app, "tools-collapsed")
    }

    func testToolDetail() throws {
        let app = try launchApp()
        open(app, "ledger")
        let edit = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Edit")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        XCTAssertTrue(app.any("改動").waitForExistence(timeout: 10), "工具詳情沒有改動")
        shot(app, "tool-detail")
        app.buttons["完成"].tap()
    }

    func testEmptyConversation() throws {
        // notes 在收起來的待命區，直接打開
        let app = try launchApp(["SR_OPEN": "FAKE-IDLE"])
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "對話頁沒有輸入框")
        XCTAssertTrue(app.any("還沒有對話").waitForExistence(timeout: 10), "沒有訊息時畫面空白")
        XCTAssertTrue(app.any("從下面打字開始").exists, "待命的空對話說明不對")
        // 直接打開（跟點推播通知同一條路）也要有標題列的名稱與狀態
        XCTAssertTrue(app.navigationBars.staticTexts["notes"].exists, "直接打開時標題列沒有名稱")
        shot(app, "empty")
    }
}
