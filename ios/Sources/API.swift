import Foundation

// 資料形狀對應 backend/app/routers/api.py 的回應。
// 這個檔是 app 裡唯一打網路的地方（跟網頁前端的 api/client.ts 同一條規則）。

struct Account: Codable, Hashable {
    let id: String?
    let label: String?
}

struct QuestionOption: Codable, Hashable {
    let label: String
    let description: String?
}

struct Question: Codable, Hashable {
    let question: String
    let header: String?
    let options: [QuestionOption]?
    let multiSelect: Bool?
}

struct Pending: Codable, Hashable {
    let kind: String
    let questions: [Question]?
    let message: String?
    /// 計畫模式交計畫（ExitPlanMode）：kind 是 permission，多這個旗子
    let plan: Bool?

    var headline: String {
        if kind == "ask", let q = questions?.first { return q.question }
        return message.map(serverText) ?? String(localized: "等你回答")
    }
}

struct SessionSummary: Codable, Identifiable, Hashable {
    let id: String
    let tty: String
    let name: String
    let cwd: String
    let account: Account
    let status: String
    let status_since: String?
    let activity: String
    let pending: Pending?
    let last_text: String
    let session_id: String?
    /// 用了多少 context（%）；那個 session 的狀態列還沒更新過就是 nil
    let context_pct: Int?
    /// 使用者標了星號（存在筆電，跟著 iTerm2 分頁走）
    let starred: Bool?
    /// 回合結束後還在跑的背景任務，一件一行（waitfor 的 label 或指令）；工作中時筆電不算、給空的
    let background: [String]?
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let role: String
    let text: String
    let tool: String?
    let ts: String?
}

struct PromptOption: Codable, Hashable {
    let key: String
    let label: String
    /// 複選題才有：核取方塊目前有沒有勾
    let checked: Bool?
}

struct Prompt: Codable, Hashable {
    let options: [PromptOption]
    let selected: String?
    let type_key: String?
    /// 複選題才有：按這個 key 會移到 Submit 再按 Enter
    let submit_key: String?
    /// 一次問好幾題、都答完之後的確認頁才有：每題答了什麼
    let review: [ReviewItem]?
}

struct ReviewItem: Codable, Hashable {
    let question: String
    let answer: String
}

struct SessionDetail: Codable {
    let id: String
    let name: String
    let cwd: String
    let account: Account
    let status: String
    let activity: String
    let pending: Pending?
    let messages: [Message]
    let total_messages: Int
    /// true：這次回的是最後一段、整串換掉；false：只是 after／before 要的那一段
    let reset: Bool?
    /// 回傳的第一則之前還有沒有更早的
    let has_more: Bool?
    let prompt: Prompt?
    /// 正在等權限的那一則工具呼叫（後端拿得準才有，見 transcript.awaiting）
    let awaiting_tool: Message?
    let screen: [String]
    let context_pct: Int?
    let starred: Bool?
}

struct SessionList: Codable {
    let sessions: [SessionSummary]
    let version: Int
}

struct Options: Codable {
    let projects: [String]
    /// 最近用過的資料夾（開著的 session＋最近從手機開過的），排在最前面
    let recent: [String]?
    let accounts: [Account]
}

struct QuotaAccount: Codable, Hashable, Identifiable {
    /// claude-bruce 這種，一個帳號的一家服務一列
    let id: String
    /// bruce／peter
    let account: String
    /// claude／codex
    let vendor: String
    let label: String
    let weekly_pct: Int?
    let weekly_resets: String?
    let short_pct: Int?
    let short_resets: String?
    let stale: Bool
    let blocked: Bool
}

struct Quota: Codable {
    let accounts: [QuotaAccount]
    let generated_at: String?
}

/// 點開一個工具呼叫看到的完整內容
struct ToolDetail: Codable {
    let tool: String
    let summary: String
    let input: [String: JSONValue]
    let output: String?
    let output_truncated: Bool
    let is_error: Bool
}

/// 工具的輸入是任意 JSON；手機只需要把字串類的欄位攤開來看
enum JSONValue: Codable, Hashable {
    case string(String), number(Double), bool(Bool), other(String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .other("…") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .other(let s): try c.encode(s)
        }
    }

    var text: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .other(let s): return s
        }
    }
}

struct SearchHit: Codable, Identifiable, Hashable {
    let id: String
    let role: String
    let tool: String?
    let snippet: String
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct API {
    let base: URL
    let token: String
    /// 展示模式：有值就全部改問這份 app 內建的假資料，不打網路（見 DemoBackend.swift）
    var demo: DemoBackend? = nil

    static func demo(_ d: DemoBackend) -> API {
        API(base: URL(string: "demo://local")!, token: "demo", demo: d)
    }

    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let data: Data, resp: URLResponse
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch let e as URLError where e.code != .cancelled {
            throw APIError(message: Self.describe(e))
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError(message: detail.map(serverText) ?? String(localized: "伺服器回 \(code)"))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// 系統的網路錯誤是英文（app 沒有在地化），換成講得出原因的中文
    static func describe(_ e: URLError) -> String {
        switch e.code {
        case .notConnectedToInternet: return String(localized: "手機沒有網路")
        case .timedOut: return String(localized: "等筆電回應逾時")
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed:
            return String(localized: "連不到筆電的服務")
        default: return String(localized: "網路錯誤（\(e.code.rawValue)）")
        }
    }

    private struct OK: Decodable { let ok: Bool }
    private struct Created: Decodable { let ok: Bool; let id: String }

    func sessions() async throws -> SessionList {
        if let demo { return await demo.sessions() }
        return try await send(request("api/sessions"), as: SessionList.self)
    }

    /// after：只要這一則之後的（省流量）；before：這一則之前的一頁（載入更早的）
    func session(_ id: String, after: String? = nil, before: String? = nil, limit: Int = 150,
                 screen: Bool = false) async throws -> SessionDetail {
        if let demo { return try await demo.session(id) }
        var comps = URLComponents(url: base.appendingPathComponent("api/sessions/\(id)"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit)),
                            URLQueryItem(name: "screen", value: screen ? "true" : "false")]
        if let after { comps.queryItems?.append(URLQueryItem(name: "after", value: after)) }
        if let before { comps.queryItems?.append(URLQueryItem(name: "before", value: before)) }
        var req = request("api/sessions/\(id)")
        req.url = comps.url
        return try await send(req, as: SessionDetail.self)
    }

    func reply(_ id: String, text: String) async throws {
        #if DEBUG
        // UI 驗收模擬筆電慢回應：確認清空、暫時訊息與收鍵盤都發生在回應之前。
        if ProcessInfo.processInfo.environment["SR_URL"] != nil,
           let delay = ProcessInfo.processInfo.environment["SR_REPLY_DELAY"].flatMap(Double.init), delay > 0 {
            try await Task.sleep(for: .seconds(min(delay, 30)))
        }
        #endif
        if let demo { return try await demo.reply(id, text: text) }
        _ = try await send(request("api/sessions/\(id)/reply", method: "POST", body: ["text": text]), as: OK.self)
    }

    /// label：按下去那顆按鈕的字。筆電會核對畫面上同一個 key 還是不是它，不是就拒絕（手機顯示的是舊畫面）
    func key(_ id: String, _ key: String, label: String? = nil) async throws {
        if let demo { return try await demo.key(id, key, label: label) }
        var body = ["key": key]
        if let label { body["label"] = label }
        _ = try await send(request("api/sessions/\(id)/key", method: "POST", body: body), as: OK.self)
    }

    func interrupt(_ id: String) async throws {
        if let demo { return try await demo.interrupt(id) }
        _ = try await send(request("api/sessions/\(id)/interrupt", method: "POST"), as: OK.self)
    }

    /// 結束那個 Claude 並關掉 iTerm2 分頁（回不來）
    func close(_ id: String) async throws {
        if let demo { return try await demo.close(id) }
        _ = try await send(request("api/sessions/\(id)/close", method: "POST"), as: OK.self)
    }

    /// 照片傳到筆電，回傳存好的絕對路徑（給 Claude 用 Read 看）
    func upload(_ id: String, jpeg: Data) async throws -> String {
        if let demo { return try await demo.upload(id) }
        struct Saved: Decodable { let path: String }
        var req = request("api/sessions/\(id)/upload", method: "POST",
                          body: ["data": jpeg.base64EncodedString(), "ext": "jpg"])
        req.timeoutInterval = 60
        return try await send(req, as: Saved.self).path
    }

    func star(_ id: String, _ starred: Bool) async throws {
        if let demo { return try await demo.star(id, starred) }
        _ = try await send(request("api/sessions/\(id)/star", method: "POST", body: ["starred": starred]), as: OK.self)
    }

    struct ServerSettings: Codable {
        let star_only_push: Bool
        let done_push: Bool

        init(star_only_push: Bool, done_push: Bool = false) {
            self.star_only_push = star_only_push
            self.done_push = done_push
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            star_only_push = try c.decode(Bool.self, forKey: .star_only_push)
            done_push = try c.decodeIfPresent(Bool.self, forKey: .done_push) ?? false
        }
    }

    func settings() async throws -> ServerSettings {
        if let demo { return await demo.settings() }
        return try await send(request("api/settings"), as: ServerSettings.self)
    }

    func setDonePush(_ on: Bool) async throws -> ServerSettings {
        if let demo { return await demo.setDonePush(on) }
        return try await send(request("api/settings", method: "POST", body: ["done_push": on]), as: ServerSettings.self)
    }

    func setStarOnlyPush(_ on: Bool) async throws -> ServerSettings {
        if let demo { return await demo.setStarOnlyPush(on) }
        return try await send(request("api/settings", method: "POST", body: ["star_only_push": on]), as: ServerSettings.self)
    }

    func quota() async throws -> Quota {
        if let demo { return await demo.quota() }
        return try await send(request("api/quota"), as: Quota.self)
    }

    /// 鎖定畫面即時狀態的推播 token。kind：update（更新正開著的）／start（讓筆電遠端開一個）
    func registerActivity(token: String, kind: String) async throws {
        if demo != nil { return }
        _ = try await send(request("api/activities", method: "POST",
                                   body: ["token": token, "env": "sandbox", "kind": kind]), as: OK.self)
    }

    func options() async throws -> Options {
        if let demo { return await demo.options() }
        return try await send(request("api/options"), as: Options.self)
    }

    /// prompt：第一句話（空的就只開 claude 等你打）
    func newSession(directory: String, account: String, prompt: String = "") async throws -> String {
        if let demo { return await demo.newSession(directory: directory, account: account, prompt: prompt) }
        return try await send(request("api/sessions", method: "POST",
                               body: ["directory": directory, "account": account, "prompt": prompt]), as: Created.self).id
    }

    func toolDetail(_ id: String, message: String) async throws -> ToolDetail {
        if let demo { return try await demo.toolDetail(id, message: message) }
        return try await send(request("api/sessions/\(id)/tools/\(message)"), as: ToolDetail.self)
    }

    func search(_ id: String, query: String) async throws -> [SearchHit] {
        if let demo { return try await demo.search(id, query: query) }
        struct Hits: Decodable { let hits: [SearchHit] }
        var comps = URLComponents(url: base.appendingPathComponent("api/sessions/\(id)/search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "q", value: query)]
        var req = request("api/sessions/\(id)/search")
        req.url = comps.url
        return try await send(req, as: Hits.self).hits
    }

    func registerDevice(token: String) async throws {
        if demo != nil { return }
        // 用 Xcode 直接裝的開發版，推播 token 屬於 sandbox 環境
        _ = try await send(request("api/devices", method: "POST", body: ["token": token, "env": "sandbox"]), as: OK.self)
    }

    /// SSE：每收到一行 data 就呼叫 onChange。連線斷掉就拋錯，由呼叫端重連。
    func events(onChange: @escaping @MainActor () -> Void) async throws {
        if let demo {
            // 展示模式：每半秒看一次假資料有沒有變，變了就照 SSE 的方式通知
            var seen = await demo.version
            await onChange()
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 500_000_000)
                let v = await demo.version
                if v != seen { seen = v; await onChange() }
            }
            return
        }
        var req = request("api/events")
        req.timeoutInterval = 60
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(message: String(localized: "事件串流連不上")) }
        for try await line in bytes.lines {
            if line.hasPrefix("data:") { await onChange() }
        }
    }
}
