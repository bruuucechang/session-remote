import XCTest

/// 假資料後端（tools/fake-backend.sh）的控制：每條測試開始前重來、讀回 app 送出去的字。
/// 網址由 tools/uitest.sh 用 TEST_RUNNER_SR_TEST_URL 帶進來；沒帶就當成模擬器連本機。
enum FakeBackend {
    static let url = ProcessInfo.processInfo.environment["SR_TEST_URL"] ?? "http://127.0.0.1:5390"
    static let token = "uitest"

    struct Entry: Decodable {
        let op: String
        let id: String
        let text: String?
        let code: Int?
        let seq: String?
        let command: String?
    }

    static func reset() throws {
        _ = try call("fake/reset", method: "POST")
    }

    static func log() throws -> [Entry] {
        struct R: Decodable { let log: [Entry] }
        return try JSONDecoder().decode(R.self, from: call("fake/log")).log
    }

    static func setScreen(_ id: String, _ text: String) throws {
        _ = try call("fake/screen", method: "POST", body: ["id": id, "text": text])
    }

    /// 同步打一次（測試裡不用 async）
    private static func call(_ path: String, method: String = "GET", body: [String: String]? = nil) throws -> Data {
        var req = URLRequest(url: URL(string: "\(url)/\(path)")!, timeoutInterval: 10)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        var out: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { out = .failure(err) }
            else if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                out = .failure(NSError(domain: "FakeBackend", code: http.statusCode,
                                       userInfo: [NSLocalizedDescriptionKey: "\(path) 回 \(http.statusCode)"]))
            } else { out = .success(data ?? Data()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 15)
        return try out.get()
    }
}

extension XCTestCase {
    /// 重來假資料、帶著假資料後端的網址開 app
    func launchApp(_ extra: [String: String] = [:]) throws -> XCUIApplication {
        try FakeBackend.reset()
        let app = XCUIApplication()
        app.launchEnvironment = ["SR_URL": FakeBackend.url, "SR_TOKEN": FakeBackend.token].merging(extra) { $1 }
        app.launch()
        return app
    }

    /// 截一張圖留在測試結果裡（tools/uitest.sh 會匯出成 png）
    func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
