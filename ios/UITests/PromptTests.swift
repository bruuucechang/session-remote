import XCTest

/// 回答題目：單選、複選、多題、確認頁、權限提示、計畫核准、信任資料夾（B4）。
/// 假畫面在 backend/tests/screens/，情境是 scenario-prompts.json（計畫核准用預設情境的 FAKE-PLAN）
final class PromptTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    /// 直接打開某個 session，等題目卡出來
    private func open(_ id: String, scenario: String = "prompts") throws -> XCUIApplication {
        let app = try launchApp(["SR_OPEN": id], scenario: scenario)
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 15), "對話頁沒有輸入框")
        return app
    }

    /// 題目卡上 label 開頭是這段字的選項按鈕（按鈕的 label 是「標籤，推薦，說明」）
    private func option(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    /// 等假後端記到某一筆送出
    private func waitSent(_ what: String, _ match: @escaping (FakeBackend.Entry) -> Bool) {
        let sent = NSPredicate { _, _ in (try? FakeBackend.log().contains(where: match)) ?? false }
        let e = expectation(for: sent, evaluatedWith: nil)
        e.expectationDescription = what
        wait(for: [e], timeout: 10)
    }

    func testNewPromptDismissesKeyboard() throws {
        // 送完字鍵盤還開著、下一題才來：選項不能被「打字中只留兩行」藏起來（2026-10-25 真機實測抓到）
        let app = try launchApp(["SR_OPEN": "FAKE-DONE"])
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        box.tap()
        box.typeText("等一下")
        try FakeBackend.setScreen("FAKE-DONE", """
             ☐ 部署
            要部署到哪裡？
            ❯ 1. Fly.io (Recommended)
              2. 自己的 VPS
              3. Type something.
            ────────────────────────────────────────
              4. Chat about this
            Enter to select · ↑/↓ to navigate · Esc to cancel
            """)
        XCTAssertTrue(option(app, "Fly.io").waitForExistence(timeout: 10), "新題目來了，選項卻被鍵盤收起來")
        shot(app, "new-prompt")
    }

    func testSingleChoice() throws {
        let app = try open("FAKE-ASK")
        XCTAssertTrue(app.staticTexts["要部署到哪裡？"].waitForExistence(timeout: 10), "沒有題目")
        XCTAssertTrue(app.staticTexts["部署"].exists, "沒有題目的標頭")
        let fly = option(app, "Fly.io")
        XCTAssertTrue(fly.exists, "沒有 Fly.io 這個選項")
        XCTAssertTrue(fly.label.contains("推薦"), "推薦的選項沒標推薦：\(fly.label)")
        XCTAssertFalse(fly.label.contains("Recommended"), "推薦標籤沒拿掉：\(fly.label)")
        XCTAssertTrue(fly.label.contains("便宜、設定少"), "選項沒有說明：\(fly.label)")
        XCTAssertFalse(option(app, "Type something").exists, "Type something 應該靠輸入框打，不是按鈕")
        XCTAssertFalse(option(app, "Chat about").exists, "Chat about this 不該出現")
        shot(app, "single")
        option(app, "自己的 VPS").tap()
        waitSent("按第 2 項送數字 2") { $0.op == "write" && $0.id == "FAKE-ASK" && $0.text == "2" }
    }

    func testTypedAnswerGoesThroughTypeSomething() throws {
        let app = try open("FAKE-ASK")
        let box = app.textViews.firstMatch
        XCTAssertTrue(app.staticTexts["要部署到哪裡？"].waitForExistence(timeout: 10))
        box.tap()
        box.typeText("Render")
        app.buttons["送出"].tap()
        // 先選 Type something（4）再打字
        waitSent("打的字送出") { $0.op == "write" && $0.text == "Render" }
        let log = try FakeBackend.log().filter { $0.id == "FAKE-ASK" && $0.op == "write" }.map { $0.text ?? "" }
        XCTAssertEqual(log, ["4", "Render"], "沒有先選 Type something")
        // 送完要收鍵盤：下一題的選項可能跟這題一模一樣（這裡畫面沒換），還是要看得到
        XCTAssertTrue(option(app, "Fly.io").waitForExistence(timeout: 10), "打字回答送出後選項被鍵盤收起來")
    }

    func testRefreshKeepsKeyboard() throws {
        // 同一題只是重新整理（hook 事件每次都會觸發）：正在打字的鍵盤不能被收掉
        let app = try open("FAKE-ASK")
        let box = app.textViews.firstMatch
        XCTAssertTrue(app.staticTexts["要部署到哪裡？"].waitForExistence(timeout: 10))
        box.tap()
        box.typeText("Ren")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // 畫面換成同一題（只差說明文字）＝觸發一次重新整理
        try FakeBackend.setScreen("FAKE-ASK", """
             ☐ 部署
            要部署到哪裡？
            ❯ 1. Fly.io (Recommended)
                 便宜
              2. 自己的 VPS
              3. Vercel
              4. Type something.
            ────────────────────────────────────────
              5. Chat about this
            Enter to select · ↑/↓ to navigate · Esc to cancel
            """)
        sleep(3)
        XCTAssertTrue(app.keyboards.firstMatch.exists, "同一題重新整理就把鍵盤收掉")
        XCTAssertEqual(box.value as? String, "Ren")
    }

    func testMultiSelectToggleAndSubmit() throws {
        let app = try open("FAKE-MULTI")
        XCTAssertTrue(app.staticTexts["要加哪些配料？（可複選）"].waitForExistence(timeout: 10), "沒有題目")
        XCTAssertEqual(option(app, "番茄").value as? String, "已勾", "勾起來的番茄沒顯示已勾")
        XCTAssertEqual(option(app, "起司").value as? String, "沒勾")
        let submit = app.buttons["送出選擇（已勾 1 項）"]
        XCTAssertTrue(submit.exists, "送出鈕沒寫勾了幾項")
        shot(app, "multi")
        option(app, "起司").tap()
        waitSent("勾起司送數字 1") { $0.op == "write" && $0.id == "FAKE-MULTI" && $0.text == "1" }
        // 終端機那邊勾起來了：畫面換成起司也打勾，手機要跟著變
        // （手機上的測試讀不到筆電的檔案，畫面直接寫在這裡；跟 multi_submit.txt 只差起司打勾）
        try FakeBackend.setScreen("FAKE-MULTI", """
             ☐ 配料
            要加哪些配料？（可複選）
              1. [✔] 起司
                     口感濃郁，加熱會融化。
            ❯ 2. [✔] 番茄
                     酸甜清爽，口感多汁。
              3. [ ] 洋蔥
                     加熱後香甜軟嫩。
              4. [ ] Type something
                 Submit
            ────────────────────────────────────────
              5. Chat about this
            Enter to select · ↑/↓ to navigate · Esc to cancel
            """)
        let two = app.buttons["送出選擇（已勾 2 項）"]
        XCTAssertTrue(two.waitForExistence(timeout: 10), "勾了之後送出鈕沒更新")
        two.tap()
        // 游標在番茄（第 2 行）→ 往下 3 行到 Submit → Enter
        waitSent("送出按 Enter") { $0.op == "ascii" && $0.id == "FAKE-MULTI" && $0.code == 13 }
        let downs = try FakeBackend.log().filter { $0.id == "FAKE-MULTI" && $0.op == "seq" }.map { $0.seq ?? "" }
        XCTAssertEqual(downs, ["[B", "[B", "[B"], "沒移到 Submit 那一行")
    }

    func testStepsShowWhichQuestion() throws {
        let app = try open("FAKE-STEPS")
        XCTAssertTrue(app.staticTexts["要加哪些配料？（可複選）"].waitForExistence(timeout: 10), "題目錯配（不是畫面上的第 2 題）")
        XCTAssertTrue(app.any("第 2／3 題").exists, "沒寫是第幾題")
        XCTAssertTrue(option(app, "起司").label.contains("濃郁的乳香"), "說明錯配：\(option(app, "起司").label)")
        shot(app, "steps")
    }

    func testReviewSubmit() throws {
        let app = try open("FAKE-REVIEW")
        XCTAssertTrue(app.any("共 3 題").waitForExistence(timeout: 10), "確認頁沒寫幾題")
        XCTAssertTrue(app.staticTexts["→ 起司, 洋蔥"].exists, "確認頁沒列出答案")
        XCTAssertTrue(option(app, "取消，回去改").exists, "確認頁的取消沒翻成中文")
        shot(app, "review")
        // 確認頁沒有可以打字的那一項：打的字會被吃掉，不給送；選項也不能因為叫出鍵盤就收起來
        // （要在按選項之前檢查：按完之後有一小段時間本來就不能送）
        let box = app.textViews.firstMatch
        box.tap()
        box.typeText("好")
        XCTAssertFalse(app.buttons["送出"].isEnabled, "確認頁還能從輸入框送字")
        XCTAssertTrue(option(app, "送出答案").exists, "點了輸入框，確認頁的選項就不見了")
        option(app, "送出答案").tap()
        waitSent("按送出答案送數字 1") { $0.op == "write" && $0.id == "FAKE-REVIEW" && $0.text == "1" }
    }

    func testPermissionPrompt() throws {
        let app = try open("FAKE-PERM")
        XCTAssertTrue(app.staticTexts["Claude 要用 Bash，允許嗎？"].waitForExistence(timeout: 10), "權限提示沒寫是哪個工具")
        XCTAssertEqual(option(app, "不允許，告訴 Claude").label, "不允許，告訴 Claude 怎麼做（按了再打字）", "拒絕並說明的那一項要是按鈕")
        shot(app, "permission")
        // 點工具那一列看完整指令
        app.buttons["看 Bash 的完整內容"].tap()
        XCTAssertTrue(app.any("rm -rf build").waitForExistence(timeout: 10), "看不到要允許的指令")
        app.buttons["完成"].tap()
        app.buttons["允許"].tap()
        waitSent("按允許送數字 1") { $0.op == "write" && $0.id == "FAKE-PERM" && $0.text == "1" }
    }

    func testPermissionWithoutToolName() throws {
        // 新版通知只寫「Claude needs your permission」：工具名要從對話最後一則工具呼叫拿（2026-10-26 v2.1.310 真機實測抓到）
        let app = try open("FAKE-PERM2")
        XCTAssertTrue(app.staticTexts["Claude 要用 Bash，允許嗎？"].waitForExistence(timeout: 10), "通知沒寫工具時標題不對")
        XCTAssertFalse(app.any("Claude needs your permission").exists, "標題還是英文")
        shot(app, "permission-rule")
        app.buttons["允許"].tap()
        waitSent("按允許送數字 1") { $0.op == "write" && $0.id == "FAKE-PERM2" && $0.text == "1" }
    }

    func testPlanApprove() throws {
        let app = try open("FAKE-PLAN", scenario: "")
        XCTAssertTrue(app.any("計畫寫好了").waitForExistence(timeout: 10), "沒有計畫核准的標題")
        XCTAssertTrue(app.staticTexts["計畫核准"].exists)
        shot(app, "plan")
        option(app, "核准，每次改檔先問我").tap()
        waitSent("按第 2 項送數字 2") { $0.op == "write" && $0.id == "FAKE-PLAN" && $0.text == "2" }
    }

    func testTrustFolder() throws {
        let app = try open("FAKE-TRUST")
        XCTAssertTrue(app.staticTexts["要信任「fresh」這個資料夾嗎？"].waitForExistence(timeout: 10), "信任資料夾沒有看得懂的標題")
        shot(app, "trust")
        option(app, "信任這個資料夾").tap()
        // 沒編號的選單：游標在第 1 項，往下一格再 Enter
        waitSent("按 Enter") { $0.op == "ascii" && $0.id == "FAKE-TRUST" && $0.code == 13 }
        let moves = try FakeBackend.log().filter { $0.id == "FAKE-TRUST" && $0.op == "seq" }.map { $0.seq ?? "" }
        XCTAssertEqual(moves, ["[B"])
    }
}
