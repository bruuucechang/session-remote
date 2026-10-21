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

    var headline: String {
        if kind == "ask", let q = questions?.first { return q.question }
        return message ?? "等你回答"
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
    let screen: [String]
    let context_pct: Int?
}

struct SessionList: Codable {
    let sessions: [SessionSummary]
    let version: Int
}

struct Options: Codable {
    let projects: [String]
    let accounts: [Account]
}

struct QuotaAccount: Codable, Hashable, Identifiable {
    let id: String
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

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct API {
    let base: URL
    let token: String

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
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError(message: detail ?? "伺服器回 \(code)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct OK: Decodable { let ok: Bool }
    private struct Created: Decodable { let ok: Bool; let id: String }

    func sessions() async throws -> SessionList {
        try await send(request("api/sessions"), as: SessionList.self)
    }

    /// after：只要這一則之後的（省流量）；before：這一則之前的一頁（載入更早的）
    func session(_ id: String, after: String? = nil, before: String? = nil, limit: Int = 150,
                 screen: Bool = false) async throws -> SessionDetail {
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
        _ = try await send(request("api/sessions/\(id)/reply", method: "POST", body: ["text": text]), as: OK.self)
    }

    func key(_ id: String, _ key: String) async throws {
        _ = try await send(request("api/sessions/\(id)/key", method: "POST", body: ["key": key]), as: OK.self)
    }

    func interrupt(_ id: String) async throws {
        _ = try await send(request("api/sessions/\(id)/interrupt", method: "POST"), as: OK.self)
    }

    /// 結束那個 Claude 並關掉 iTerm2 分頁（回不來）
    func close(_ id: String) async throws {
        _ = try await send(request("api/sessions/\(id)/close", method: "POST"), as: OK.self)
    }

    /// 照片傳到筆電，回傳存好的絕對路徑（給 Claude 用 Read 看）
    func upload(_ id: String, jpeg: Data) async throws -> String {
        struct Saved: Decodable { let path: String }
        var req = request("api/sessions/\(id)/upload", method: "POST",
                          body: ["data": jpeg.base64EncodedString(), "ext": "jpg"])
        req.timeoutInterval = 60
        return try await send(req, as: Saved.self).path
    }

    func quota() async throws -> Quota {
        try await send(request("api/quota"), as: Quota.self)
    }

    /// 鎖定畫面即時狀態的推播 token。kind：update（更新正開著的）／start（讓筆電遠端開一個）
    func registerActivity(token: String, kind: String) async throws {
        _ = try await send(request("api/activities", method: "POST",
                                   body: ["token": token, "env": "sandbox", "kind": kind]), as: OK.self)
    }

    func options() async throws -> Options {
        try await send(request("api/options"), as: Options.self)
    }

    func newSession(directory: String, account: String) async throws -> String {
        try await send(request("api/sessions", method: "POST", body: ["directory": directory, "account": account]), as: Created.self).id
    }

    func registerDevice(token: String) async throws {
        // 用 Xcode 直接裝的開發版，推播 token 屬於 sandbox 環境
        _ = try await send(request("api/devices", method: "POST", body: ["token": token, "env": "sandbox"]), as: OK.self)
    }

    /// SSE：每收到一行 data 就呼叫 onChange。連線斷掉就拋錯，由呼叫端重連。
    func events(onChange: @escaping @MainActor () -> Void) async throws {
        var req = request("api/events")
        req.timeoutInterval = 60
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(message: "事件串流連不上") }
        for try await line in bytes.lines {
            if line.hasPrefix("data:") { await onChange() }
        }
    }
}
