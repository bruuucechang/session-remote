import XCTest

final class MobileUXEdgeTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testMarkedTextClearsAndFailureRestoresDraft() throws {
        let app = try launchApp(["SR_OPEN": "FAKE-DONE", "SR_REPLY_DELAY": "4",
                                 "SR_MARKED_TEXT": "尚未選字"], scenario: "write-fails")
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        box.tap()
        expectation(for: NSPredicate(format: "value == %@", "尚未選字"), evaluatedWith: box)
        waitForExpectations(timeout: 5)
        app.buttons["送出"].tap()
        XCTAssertEqual(box.value as? String, "")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.staticTexts["送出中"].exists)
        XCTAssertTrue(app.any("送字失敗").waitForExistence(timeout: 10))
        XCTAssertEqual(box.value as? String, "尚未選字")
        XCTAssertFalse(app.staticTexts["送出中"].exists)
        shot(app, "marked-restored")

    }

    func testPendingReplyExpiresWithoutTranscript() throws {
        let app = try launchApp(["SR_OPEN": "FAKE-IDLE", "SR_REPLY_DELAY": "3"])
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        box.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        box.typeText("尚未寫入紀錄")
        app.buttons["送出"].tap()
        let pending = app.staticTexts["送出中"]
        XCTAssertTrue(pending.exists)
        XCTAssertFalse(app.any("還沒有對話").exists, "暫時訊息被空狀態蓋住")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: pending)
        waitForExpectations(timeout: 17)
        XCTAssertFalse(app.staticTexts["尚未寫入紀錄"].exists)
    }

    func testDemoReplyAcknowledgesWithoutDuplicates() throws {
        let app = try launchApp(["SR_DEMO": "1", "SR_OPEN": "demo-blog", "SR_REPLY_DELAY": "3"])
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        box.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        box.typeText("這一句只出現一次")
        app.buttons["送出"].tap()
        XCTAssertTrue(app.staticTexts["送出中"].exists)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["送出中"])
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.staticTexts.matching(identifier: "這一句只出現一次").count, 1)
        XCTAssertEqual(box.value as? String, "")
        shot(app, "demo-acknowledged")
    }

    func testDemoListAnswerChangesStatus() throws {
        let app = try launchApp(["SR_DEMO": "1"])
        let choice = app.buttons["quick-demo-shop-1"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        XCTAssertTrue(choice.label.contains("推薦"))
        XCTAssertFalse(choice.label.contains("Recommended"))
        choice.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: choice)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("shop")
        XCTAssertTrue(app.any("部署好了").waitForExistence(timeout: 10))
        shot(app, "list-answered")
    }

    func testListAnswerErrorStaysOnItsCard() throws {
        let app = try launchApp(scenario: "mobile-ux-error")
        let choice = app.buttons["quick-FAKE-ASK-1"]
        XCTAssertTrue(choice.waitForExistence(timeout: 15))
        choice.tap()
        let card = app.row("shop")
        XCTAssertTrue(card.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "送字失敗")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(choice.isEnabled)
        XCTAssertFalse(app.textViews.firstMatch.exists)
        shot(app, "list-error")
    }

    func testDonePushDefaultsOffAndRevealsStarSetting() throws {
        let app = try launchApp(["SR_DEMO": "1"])
        let gear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "設定")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()
        let done = app.switches["完工也推播"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertEqual(done.value as? String, "0")
        XCTAssertFalse(app.switches["完工只推標星號的"].exists)
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.switches["完工只推標星號的"].waitForExistence(timeout: 5))
        shot(app, "done-push-on")
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.switches["完工只推標星號的"].exists)
    }
}
