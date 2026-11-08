import XCTest

/// 列表：分組與排序、搜尋、星號、關分頁、空／連不上、額度卡（B2）
final class ListTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testGroupsInOrderAndIdleFolded() throws {
        let app = try launchApp(scenario: "many")
        let titles = ["星號 · 1", "等你回答 · 1", "背景跑 · 1", "完工 · 1", "待命 · 6"]
        let headers = titles.map { app.any($0) }
        XCTAssertTrue(headers[0].waitForExistence(timeout: 15), "沒有星號區")
        for (t, h) in zip(titles, headers) { XCTAssertTrue(h.exists, "少了「\(t)」") }
        let ys = headers.map(\.frame.minY)
        XCTAssertEqual(ys, ys.sorted(), "分組順序不對：\(zip(titles, ys).map { "\($0) \($1)" })")
        // 收合狀態記在手機上（@AppStorage），測試前後要一樣：點兩下，各看一次
        let wasOpen = app.staticTexts["palrogue"].exists
        shot(app, wasOpen ? "expanded" : "folded")
        headers[4].tap()
        let flipped = NSPredicate(format: "exists == %@", NSNumber(value: !wasOpen))
        expectation(for: flipped, evaluatedWith: app.staticTexts["palrogue"])
        waitForExpectations(timeout: 5)
        shot(app, wasOpen ? "folded" : "expanded")
        headers[4].tap()
    }

    func testSearchFindsFoldedIdle() throws {
        let app = try launchApp(scenario: "many")
        XCTAssertTrue(app.staticTexts["atlas"].waitForExistence(timeout: 15))
        app.swipeDown()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("palrogue")
        XCTAssertTrue(app.staticTexts["palrogue"].waitForExistence(timeout: 5), "搜尋找不到收起來的待命")
        XCTAssertFalse(app.staticTexts["atlas"].exists, "搜尋沒有濾掉不相干的")
        shot(app, "search")
    }

    func testSearchWithNoMatchSaysSo() throws {
        let app = try launchApp(scenario: "many")
        XCTAssertTrue(app.staticTexts["atlas"].waitForExistence(timeout: 15))
        app.swipeDown()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("zzz")
        XCTAssertTrue(app.any("找不到").waitForExistence(timeout: 5), "搜尋沒結果時畫面空白")
        shot(app, "search-empty")
    }

    func testWaitingAboveQuota() throws {
        let app = try launchApp()
        let codex = app.staticTexts["Codex"]
        XCTAssertTrue(codex.waitForExistence(timeout: 15))
        let waiting = app.any("等你回答 · 1")
        XCTAssertTrue(waiting.exists)
        XCTAssertLessThan(waiting.frame.minY, codex.frame.minY, "等你回答要排在額度卡上面")
    }

    func testStarMovesRowToTop() throws {
        let app = try launchApp(scenario: "many")
        let row = app.row("ledger")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeRight()
        app.buttons["標星號"].tap()
        XCTAssertTrue(app.any("星號 · 2").waitForExistence(timeout: 10), "標了星號沒移到星號區")
        shot(app, "starred")
    }

    func testCloseTab() throws {
        let app = try launchApp(scenario: "many")
        let row = app.row("atlas")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeLeft()
        app.buttons["關掉"].tap()
        app.buttons["結束 Claude 並關掉分頁"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["atlas"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(try FakeBackend.log().contains { $0.op == "close" && $0.id == "MANY-3" }, "後端沒收到關分頁")
    }

    func testCloseFailureShowsOnThatRow() throws {
        let app = try launchApp(scenario: "many")
        let row = app.row("ledger")
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.swipeLeft()
        app.buttons["關掉"].tap()
        app.buttons["結束 Claude 並關掉分頁"].tap()
        let err = app.any("關不掉")
        XCTAssertTrue(err.waitForExistence(timeout: 15), "關分頁失敗沒有錯誤訊息")
        XCTAssertTrue(app.row("ledger").frame.contains(CGPoint(x: err.frame.midX, y: err.frame.midY)),
                      "錯誤沒出現在那一列：錯誤 \(err.frame)，那一列 \(app.row("ledger").frame)")
        shot(app, "close-failed")
    }

    func testDoneRowSaysWhenItFinished() throws {
        let app = try launchApp(scenario: "many")
        // 整列的字合在 NavigationLink 按鈕的 label 裡：「ledger、昨天 17:40 做完、bruce、…」（分隔符號跟著語言）
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ledger")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        // 假資料的 ledger 是 10/24 09:40（UTC）做完的，早就超過一小時：要寫出幾點，不是「幾小時前」
        XCTAssertTrue(row.label.contains("完工"), "完工的那一列沒寫什麼時候完工：\(row.label)")
        XCTAssertFalse(row.label.contains("小時前"), "做完很久了還是寫「幾小時前」：\(row.label)")
        shot(app, "done-when")
    }

    /// 回合結束但背景還在跑的，要跟完工的分開，而且講得出在跑什麼（背景完工標示，2026-11-08）
    func testBackgroundSeparateFromDone() throws {
        let app = try launchApp(scenario: "many")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "pager")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("waitfor next-champ"), "背景跑的那一列沒寫在跑什麼：\(row.label)")
        XCTAssertTrue(row.label.contains("共 2 件"), "背景好幾件沒講件數：\(row.label)")
        XCTAssertFalse(row.label.contains("完工"), "背景還在跑卻標完工：\(row.label)")
        let bg = app.any("背景跑 · 1"), done = app.any("完工 · 1")
        XCTAssertTrue(bg.exists && done.exists, "背景跑與完工沒有分兩區")
        // 等你回答的同時背景在跑：狀態照舊，多一個「背景 1」小標
        let atlas = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "atlas")).firstMatch
        XCTAssertTrue(atlas.label.contains("背景 1"), "等你回答的那一列沒標背景數：\(atlas.label)")
        shot(app, "background")
    }

    func testEmpty() throws {
        let app = try launchApp(scenario: "empty")
        XCTAssertTrue(app.any("沒有 session").waitForExistence(timeout: 15), "空列表沒有說明")
        shot(app, "empty")
    }

    func testUnreachable() throws {
        let app = try launchApp(["SR_URL": "http://127.0.0.1:9"])
        XCTAssertTrue(app.any("連不上筆電").waitForExistence(timeout: 20), "連不上時沒有說明")
        XCTAssertTrue(app.buttons["再試一次"].exists, "連不上時沒有重試鈕")
        shot(app, "unreachable")
    }

    func testQuotaCard() throws {
        let app = try launchApp()
        XCTAssertTrue(app.staticTexts["Codex"].waitForExistence(timeout: 15), "額度卡沒出現")
        XCTAssertTrue(app.staticTexts["93%"].exists)
        shot(app, "quota")
    }
}
