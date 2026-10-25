import XCTest

/// B5 實測：連真的筆電服務，在測試資料夾開一個真的 Claude session，從手機把每種互動做一次。
/// 只由 tools/livetest.sh 帶 SR_LIVE_URL／SR_LIVE_TOKEN／SR_LIVE_DIR 進來才跑，平常的 uitest 一律略過。
/// 安全：每一步動手之前都從 API 確認畫面上的 session 就是 SR_LIVE_DIR 那一個（使用者的 session 只能看）。
final class LiveTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private var url: String { env["SR_LIVE_URL"] ?? "" }
    private var token: String { env["SR_LIVE_TOKEN"] ?? "" }
    private var dir: String { env["SR_LIVE_DIR"] ?? "" }
    private var app: XCUIApplication!
    private var sid = ""

    override func setUpWithError() throws {
        try XCTSkipIf(url.isEmpty || token.isEmpty || dir.isEmpty, "沒帶 SR_LIVE_*：實測只由 tools/livetest.sh 跑")
        // 測試資料夾一定要是 tools/livetest.sh 開的那種，碰到別的資料夾就不跑
        XCTAssertTrue(dir.contains("/Projects/.uitest-sandbox/"), "SR_LIVE_DIR 不是測試資料夾：\(dir)")
        continueAfterFailure = false
    }

    // MARK: 真的筆電服務

    struct Summary: Decodable { let id: String; let cwd: String; let status: String }
    struct Detail: Decodable { let id: String; let cwd: String; let status: String; let messages: [M] }
    struct M: Decodable { let role: String; let text: String; let tool: String? }

    private func get<T: Decodable>(_ path: String, as: T.Type) throws -> T {
        var req = URLRequest(url: URL(string: "\(url)/\(path)")!, timeoutInterval: 15)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        var out: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { d, r, e in
            if let e { out = .failure(e) }
            else if let h = r as? HTTPURLResponse, h.statusCode != 200 {
                out = .failure(NSError(domain: "Live", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: "\(path) 回 \(h.statusCode)"]))
            } else { out = .success(d ?? Data()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        return try JSONDecoder().decode(T.self, from: out.get())
    }

    private func sandboxSessions() throws -> [Summary] {
        struct L: Decodable { let sessions: [Summary] }
        return try get("api/sessions", as: L.self).sessions.filter { $0.cwd == dir }
    }

    private func detail() throws -> Detail { try get("api/sessions/\(sid)?limit=40&screen=false", as: Detail.self) }

    /// 動手之前：這一頁一定是測試 session（標題列是測試資料夾的名字），不是就停
    private func guardSandbox() throws {
        let d = try detail()
        XCTAssertEqual(d.cwd, dir, "對話頁不是測試 session，停手")
        // 標題列是 session 名稱的專案那段：還沒取名時是資料夾名（run-…），取了名是「.uitest-sandbox｜…」
        let name = (dir as NSString).lastPathComponent
        let title = NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", name, ".uitest-sandbox")
        XCTAssertTrue(app.navigationBars.staticTexts.matching(title).firstMatch.exists, "標題列不是測試 session，停手")
    }

    /// 等某個條件成立（Claude 回應要時間）
    private func until(_ what: String, timeout: TimeInterval = 120, _ ok: @escaping () -> Bool) {
        let e = expectation(for: NSPredicate { _, _ in ok() }, evaluatedWith: nil)
        e.expectationDescription = what
        wait(for: [e], timeout: timeout)
    }

    private func option(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
    }

    private func tapOption(_ label: String, timeout: TimeInterval = 120) throws {
        let b = option(label)
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "等不到選項「\(label)」")
        try guardSandbox()
        b.tap()
    }

    private func send(_ text: String) throws {
        let box = app.textViews.firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 30))
        try guardSandbox()
        box.tap()
        box.typeText(text)
        // 長字串剛打完時點送出偶爾沒反應（2026-10-26 真機一次）：送出成功會清空輸入框，沒清空而且還能按就再點一次
        let send = app.buttons["送出"]
        for _ in 0..<3 {
            send.tap()
            let cleared = expectation(for: NSPredicate(format: "value == '' OR value == nil"), evaluatedWith: box)
            if XCTWaiter.wait(for: [cleared], timeout: 5) == .completed || !send.isEnabled { return }
        }
        XCTFail("按了三次送出都沒送出去")
    }

    /// 這一輪做完：狀態回到做完或待命
    private func waitIdle(_ what: String, timeout: TimeInterval = 180) {
        until(what, timeout: timeout) { (try? self.detail()).map { ["done", "idle"].contains($0.status) } ?? false }
    }

    private func transcriptHas(_ s: String) -> Bool {
        ((try? detail())?.messages ?? []).contains { $0.text.contains(s) }
    }

    // MARK: 一整輪

    func testLiveTour() throws {
        XCTAssertTrue(try sandboxSessions().isEmpty, "測試資料夾已經有 session 開著，先關掉再跑")
        app = XCUIApplication()
        app.launchEnvironment = ["SR_URL": url, "SR_TOKEN": token, "SR_NEW": "1", "SR_DIR": dir]
        app.launch()

        // 1. 開新 session 帶第一句話
        let first = app.textFields.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), "開新 session 沒有第一句話的欄位")
        first.tap()
        first.typeText("請立刻用 AskUserQuestion 問我一題單選：header「顏色」，題目「要哪個顏色？」，選項紅、綠。不要做別的事。")
        app.buttons["開始"].tap()
        until("測試 session 開起來", timeout: 60) { ((try? self.sandboxSessions()) ?? []).count == 1 }
        sid = try sandboxSessions()[0].id
        shot(app, "1-opened")

        // 2. 信任資料夾（新資料夾一定會問）
        try tapOption("信任這個資料夾", timeout: 60)

        // 3. 單選
        XCTAssertTrue(app.staticTexts["要哪個顏色？"].waitForExistence(timeout: 120), "沒出現單選題")
        shot(app, "3-single")
        try tapOption("綠")
        waitIdle("單選答完")
        XCTAssertTrue(transcriptHas("綠"), "紀錄裡沒有選的答案")

        // 4. 打字送出＋複選＋多題＋確認頁
        try send("請用 AskUserQuestion 一次問兩題：第一題 header「配料」multiSelect 複選，題目「要加哪些配料？」，選項起司、番茄；第二題 header「大小」單選，題目「要哪個大小？」，選項大、小。不要做別的事。")
        XCTAssertTrue(app.staticTexts["要加哪些配料？"].waitForExistence(timeout: 120), "沒出現複選題")
        try tapOption("起司")
        until("起司打勾", timeout: 20) { self.option("起司").value as? String == "已勾" }
        try tapOption("番茄")
        until("番茄打勾", timeout: 20) { self.option("番茄").value as? String == "已勾" }
        shot(app, "4-multi")
        let next = app.buttons["送出選擇（已勾 2 項）"]
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        try guardSandbox()
        next.tap()
        XCTAssertTrue(app.staticTexts["要哪個大小？"].waitForExistence(timeout: 30), "複選送出後沒到第 2 題")
        try tapOption("大")
        XCTAssertTrue(app.any("共 2 題").waitForExistence(timeout: 30), "沒出現確認頁")
        shot(app, "4-review")
        try tapOption("送出答案")
        waitIdle("多題答完")
        XCTAssertTrue(transcriptHas("起司") && transcriptHas("大"), "紀錄裡沒有多題的答案")

        // 5. 權限提示（測試資料夾的設定讓 touch 一定要問）
        try send("請用 Bash 執行 touch uitest-ok.txt，只做這件事。")
        XCTAssertTrue(app.staticTexts["Claude 要用 Bash，允許嗎？"].waitForExistence(timeout: 120), "沒出現權限提示")
        shot(app, "5-permission")
        let allow = app.buttons["允許"]
        try guardSandbox()
        allow.tap()
        waitIdle("touch 做完")

        // 6. 工作中按中斷（Esc）
        try send("請用 Bash 執行 sleep 90，只做這件事。")
        let stop = app.buttons["中斷"]
        XCTAssertTrue(stop.waitForExistence(timeout: 120), "工作中沒有中斷鈕")
        shot(app, "6-working")
        try guardSandbox()
        stop.tap()
        until("中斷後回到待命", timeout: 30) { (try? self.detail())?.status == "idle" }

        // 7. 關分頁
        try guardSandbox()
        app.buttons["更多操作"].tap()
        app.buttons["關掉這個 session"].tap()
        app.buttons["關掉"].tap()
        until("分頁關掉", timeout: 30) { (try? self.sandboxSessions())?.isEmpty ?? false }
        shot(app, "7-closed")
    }
}
