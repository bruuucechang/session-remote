import XCTest

final class MobileUXTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSendClearsImmediatelyAndDismissesKeyboard() throws {
        let app = try launchApp(["SR_OPEN": "FAKE-DONE", "SR_REPLY_DELAY": "5"])
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        box.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        box.typeText("立刻送出這一句")
        app.buttons["送出"].tap()
        XCTAssertEqual(box.value as? String, "", "不應等筆電回應才清空")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "送出後鍵盤沒有收起")
        XCTAssertTrue(app.staticTexts["送出中"].exists, "沒有暫時的自己的訊息")
        XCTAssertTrue(app.staticTexts["立刻送出這一句"].exists)
        shot(app, "sending")
    }

    func testListSingleChoiceSendsOriginalLabel() throws {
        let app = try launchApp(scenario: "prompts")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("shop\n")
        let option = app.buttons["quick-FAKE-ASK-2"]
        XCTAssertTrue(option.waitForExistence(timeout: 15), "列表沒有單選選項")
        XCTAssertTrue(option.label.contains("自己的 VPS"))
        let choices = (1...3).map { app.buttons["quick-FAKE-ASK-\($0)"] }
        for choice in choices {
            XCTAssertGreaterThanOrEqual(choice.frame.height, 44)
            XCTAssertGreaterThanOrEqual(choice.frame.minX, 0)
            XCTAssertLessThanOrEqual(choice.frame.maxX, app.frame.width)
        }
        XCTAssertLessThanOrEqual(choices[0].frame.maxY, choices[1].frame.minY)
        XCTAssertLessThanOrEqual(choices[1].frame.maxY, choices[2].frame.minY)
        shot(app, "list-choices")
        option.tap()
        let sent = NSPredicate { _, _ in
            (try? FakeBackend.log().contains { $0.op == "write" && $0.id == "FAKE-ASK" && $0.text == "2" }) ?? false
        }
        expectation(for: sent, evaluatedWith: nil)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.textViews.firstMatch.exists, "按選項卻開了對話頁")
    }

    func testListMultiSelectRequiresDetail() throws {
        let app = try launchApp(scenario: "prompts")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("pizza")
        XCTAssertTrue(app.staticTexts["點進去回答"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["quick-FAKE-MULTI-1"].exists)
        shot(app, "list-multi")
    }
}
