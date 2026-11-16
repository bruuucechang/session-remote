import XCTest

/// 展示模式（公開版 B7）：配對頁按「先看看」→ 內建假資料的列表、對話、回答題目 → 設定頁退出
final class DemoTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func option(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func enterDemo() throws -> XCUIApplication {
        let app = try launchApp(["SR_FIRSTRUN": "1"])
        let demo = app.buttons["先看看（展示模式）"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "配對頁沒有「先看看」")
        demo.tap()
        XCTAssertTrue(app.staticTexts["shop"].waitForExistence(timeout: 10), "展示模式沒有假資料列表")
        XCTAssertTrue(app.any("展示模式").exists, "列表上沒講這是展示模式")
        shot(app, "demo-list")
        return app
    }

    /// 英文介面（公開版 B8）：手機語言英文時配對頁、列表分區、題目卡、回答後的對話都是英文
    func testEnglishDemo() throws {
        let app = try launchApp(["SR_FIRSTRUN": "1"], language: "en")
        let demo = app.buttons["Take a Look (Demo Mode)"]
        XCTAssertTrue(demo.waitForExistence(timeout: 10), "英文配對頁沒有「Take a Look」")
        demo.tap()
        XCTAssertTrue(app.staticTexts["shop"].waitForExistence(timeout: 10), "展示模式沒有假資料列表")
        XCTAssertTrue(app.any("Waiting for you").exists, "分區標題不是英文")
        XCTAssertFalse(app.any("等你回答").exists, "英文介面還有中文分區標題")
        shot(app, "en-list")
        app.row("shop").tap()
        let fly = option(app, "Fly.io")
        XCTAssertTrue(fly.waitForExistence(timeout: 10), "題目卡沒出來")
        XCTAssertTrue(app.any("Where should it be deployed?").exists, "假資料題目不是英文")
        fly.tap()
        XCTAssertTrue(app.any("Chose: Fly.io").waitForExistence(timeout: 10), "按了選項對話沒變（或不是英文）")
        shot(app, "en-answered")

        // 設定頁的狀態值是 String 傳進 LabeledContent(value:)，不會自己翻（PR #31 Codex 審查抓到）
        app.navigationBars.buttons.firstMatch.tap()
        let gear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Settings")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5), "英文列表沒有 Settings 鈕")
        gear.tap()
        XCTAssertTrue(app.any("Live Updates").waitForExistence(timeout: 5), "設定頁欄位不是英文")
        XCTAssertFalse(app.any("註冊").exists, "設定頁的推播狀態還是中文")
        XCTAssertFalse(app.any("連線").exists, "設定頁的連線狀態還是中文")
        shot(app, "en-settings")
    }

    func testAnswerQuestionAndExit() throws {
        let app = try enterDemo()
        app.row("shop").tap()
        let fly = option(app, "Fly.io")
        XCTAssertTrue(fly.waitForExistence(timeout: 10), "題目卡沒出來")
        shot(app, "demo-ask")
        fly.tap()
        XCTAssertTrue(app.any("選了：Fly.io").waitForExistence(timeout: 10), "按了選項對話沒變")
        XCTAssertTrue(app.any("部署好了").waitForExistence(timeout: 10), "沒有接著完工")
        XCTAssertFalse(fly.exists, "答完題目卡還在")
        shot(app, "demo-answered")

        app.navigationBars.buttons.firstMatch.tap()
        let gear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "設定")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        // 列表上方也有一顆同名的（被設定頁蓋住），點看得到的那顆
        let exits = app.buttons.matching(identifier: "退出展示模式")
        let two = expectation(for: NSPredicate(format: "count >= 2"), evaluatedWith: exits)
        wait(for: [two], timeout: 5)
        let exit = (0..<exits.count).map { exits.element(boundBy: $0) }.first { $0.isHittable }
        XCTAssertNotNil(exit, "設定頁沒有退出展示模式")
        exit?.tap()
        XCTAssertTrue(app.buttons["先看看（展示模式）"].waitForExistence(timeout: 10), "退出後沒回到配對頁")
    }

    /// 展示模式裡直接配對：假資料（尤其快取 60 秒的額度卡）不能留在真的列表上（PR #30 Codex 第三輪）
    func testPairFromDemoDropsFakeData() throws {
        let app = try enterDemo()
        XCTAssertTrue(app.any("personal").waitForExistence(timeout: 10), "展示模式沒有假額度，測不出來")
        let gear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "設定")).firstMatch
        gear.tap()
        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        field.typeText(FakeBackend.token)
        app.buttons["儲存並連線"].tap()
        XCTAssertTrue(app.staticTexts["hello"].waitForExistence(timeout: 15), "配對後沒進真的列表")
        XCTAssertFalse(app.any("展示模式").exists, "配對後還在展示模式")
        XCTAssertFalse(app.any("personal").exists, "展示模式的假額度留在真的列表上")
        shot(app, "demo-paired")
    }

    func testPermissionPrompt() throws {
        let app = try enterDemo()
        app.row("api").tap()
        let allow = option(app, "允許")
        XCTAssertTrue(allow.waitForExistence(timeout: 10), "權限提示沒出來")
        allow.tap()
        XCTAssertTrue(app.any("測試全過").waitForExistence(timeout: 10), "允許之後沒有反應")
        shot(app, "demo-perm-done")
    }
}
