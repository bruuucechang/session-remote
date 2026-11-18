import Foundation

/// 展示模式的資料來源：還沒裝筆電端的人（和 App Store 審核員）在配對頁按「先看看」就用這份。
/// 全部是 app 內建的假資料、不連網；回答題目、送字、標星號都只改這裡的狀態，看起來像真的筆電在回應。
/// 形狀照 backend 的回應（API.swift 的 struct），情境參考 backend/tests/fixtures/uitest/scenario-*.json。
@MainActor
final class DemoBackend {
    private struct Demo {
        var id: String
        var name: String
        var cwd: String
        var account: String
        var status: String
        var since: Date
        var activity: String = ""
        var pending: Pending?
        var prompt: Prompt?
        var awaiting: Message?
        var messages: [Message]
        var context: Int?
        var starred = false
        /// 第幾輪工作：延遲完工只准完成自己那一輪（中斷後馬上又送一句，舊的那輪不能搶走新的）
        var turn = 0
    }

    private var items: [Demo]
    private var starOnly = false
    private var donePush = false
    /// 每次狀態變了就 +1；events() 看到變了就通知畫面重抓（模擬筆電的 SSE）
    private(set) var version = 1
    private var serial = 0

    init(now: Date = Date()) {
        func ago(_ min: Double) -> Date { now.addingTimeInterval(-min * 60) }
        func msg(_ id: String, _ role: String, _ text: String, tool: String? = nil, _ min: Double) -> Message {
            Message(id: id, role: role, text: text, tool: tool, ts: Self.iso(ago(min)))
        }
        let deploy = Question(
            question: String(localized: "要部署到哪裡？"), header: String(localized: "部署"),
            options: [QuestionOption(label: "Fly.io (Recommended)", description: String(localized: "便宜、設定少，有免費額度")),
                      QuestionOption(label: String(localized: "自己的 VPS"), description: String(localized: "要自己裝 Docker 與憑證")),
                      QuestionOption(label: "Vercel", description: String(localized: "只適合前端"))],
            multiSelect: false)
        let testCall = msg("api-t2", "tool", "npm test", tool: "Bash", 1)
        items = [
            Demo(id: "demo-shop", name: String(localized: "shop｜把網站部署上線"), cwd: "~/Projects/shop", account: "work",
                 status: "waiting", since: ago(3),
                 pending: Pending(kind: "ask", questions: [deploy], message: nil, plan: nil),
                 prompt: Prompt(options: [PromptOption(key: "1", label: "Fly.io (Recommended)", checked: nil),
                                          PromptOption(key: "2", label: String(localized: "自己的 VPS"), checked: nil),
                                          PromptOption(key: "3", label: "Vercel", checked: nil),
                                          PromptOption(key: "4", label: "Type something.", checked: nil)],
                                selected: "1", type_key: "4", submit_key: nil, review: nil),
                 messages: [
                    msg("shop-u1", "user", String(localized: "幫我把這個專案部署上線"), 9),
                    msg("shop-t1", "tool", "package.json", tool: "Read", 8),
                    msg("shop-t2", "tool", "npm run build", tool: "Bash", 7),
                    msg("shop-a1", "assistant", String(localized: "建置過了，產出在 `dist/`（1.2 MB）。部署之前先問一下你想放在哪裡。"), 4),
                 ], context: 31),
            Demo(id: "demo-api", name: String(localized: "api｜修好登入逾時"), cwd: "~/Projects/api", account: "work",
                 status: "waiting", since: ago(1),
                 pending: Pending(kind: "permission", questions: nil, message: String(localized: "Claude 想執行 npm test"), plan: nil),
                 prompt: Prompt(options: [PromptOption(key: "1", label: "Yes", checked: nil),
                                          PromptOption(key: "2", label: "Yes, and don't ask again for npm test commands", checked: nil),
                                          PromptOption(key: "3", label: "No, and tell Claude what to do differently (esc)", checked: nil)],
                                selected: "1", type_key: nil, submit_key: nil, review: nil),
                 awaiting: testCall,
                 messages: [
                    msg("api-u1", "user", String(localized: "登入一直逾時，查一下原因"), 12),
                    msg("api-t1", "tool", "src/auth/session.ts", tool: "Read", 10),
                    msg("api-a1", "assistant", String(localized: "找到了：session 的有效時間寫成 30 秒（應該是 30 分鐘）。我改好了，跑一次測試確認。"), 3),
                    msg("api-e1", "tool", "src/auth/session.ts", tool: "Edit", 2),
                    testCall,
                 ], context: 58),
            Demo(id: "demo-atlas", name: String(localized: "atlas｜匯入十月的行程"), cwd: "~/Projects/atlas", account: "personal",
                 status: "working", since: ago(2), activity: String(localized: "Bash：跑測試"),
                 messages: [
                    msg("atlas-u1", "user", String(localized: "匯入十月的行程，跑一次測試"), 6),
                    msg("atlas-t1", "tool", "python import.py data/october.csv", tool: "Bash", 4),
                    msg("atlas-a1", "assistant", String(localized: "匯入了 23 筆行程，接著跑測試。"), 3),
                    msg("atlas-t2", "tool", "pytest -q", tool: "Bash", 2),
                 ], context: 12),
            Demo(id: "demo-notes", name: String(localized: "notes｜整理會議紀錄"), cwd: "~/Projects/notes", account: "personal",
                 status: "done", since: ago(25),
                 messages: [
                    msg("notes-u1", "user", String(localized: "把今天三場會議的紀錄整理成一份待辦清單"), 40),
                    msg("notes-t1", "tool", "meetings/2026-11-16.md", tool: "Read", 38),
                    msg("notes-t2", "tool", "todo.md", tool: "Write", 30),
                    msg("notes-a1", "assistant", String(localized: "整理好了，寫在 `todo.md`：\n\n- 週五前寄報價單給客戶\n- 下週一前改好首頁文案\n- 約設計師討論新圖示\n\n共 3 件，都標了負責人和期限。"), 25),
                 ], context: 22, starred: true),
            Demo(id: "demo-blog", name: "blog", cwd: "~/Projects/blog", account: "personal",
                 status: "idle", since: ago(180), messages: [], context: nil),
        ]
    }

    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private func index(_ id: String) throws -> Int {
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw APIError(message: String(localized: "展示模式沒有這個 session")) }
        return i
    }

    private func nextID(_ prefix: String) -> String {
        serial += 1
        return "\(prefix)-\(serial)"
    }

    private func changed() { version += 1 }

    private func append(_ i: Int, _ role: String, _ text: String, tool: String? = nil) {
        items[i].messages.append(Message(id: nextID(items[i].id), role: role, text: text, tool: tool, ts: Self.iso(Date())))
    }

    /// 回答完：先變「工作中」，一會兒之後完工並回一句話（像筆電上的 Claude 接著做事）
    private func work(_ i: Int, activity: String, finish: String) {
        let id = items[i].id
        items[i].pending = nil
        items[i].prompt = nil
        items[i].awaiting = nil
        items[i].status = "working"
        items[i].activity = activity
        items[i].since = Date()
        items[i].turn += 1
        let turn = items[i].turn
        changed()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self, let j = self.items.firstIndex(where: { $0.id == id }),
                  self.items[j].turn == turn, self.items[j].status == "working" else { return }
            self.append(j, "assistant", finish)
            self.items[j].status = "done"
            self.items[j].activity = ""
            self.items[j].since = Date()
            self.changed()
        }
    }

    // MARK: 對應 API 的每個方法

    func sessions() -> SessionList {
        let list = items.map { d in
            SessionSummary(id: d.id, tty: "", name: d.name, cwd: d.cwd, account: Account(id: d.account, label: d.account),
                           status: d.status, status_since: Self.iso(d.since), activity: d.activity, pending: d.pending,
                           last_text: d.messages.last(where: { $0.role == "assistant" })?.text ?? "",
                           session_id: d.id, context_pct: d.context, starred: d.starred, background: nil)
        }
        return SessionList(sessions: list, version: version)
    }

    /// 假資料很少，每次都整串給（reset），不分頁
    func session(_ id: String) throws -> SessionDetail {
        let d = items[try index(id)]
        return SessionDetail(id: d.id, name: d.name, cwd: d.cwd, account: Account(id: d.account, label: d.account),
                             status: d.status, activity: d.activity, pending: d.pending, messages: d.messages,
                             total_messages: d.messages.count, reset: true, has_more: false, prompt: d.prompt,
                             awaiting_tool: d.awaiting, screen: [String(localized: "（展示模式沒有真的終端機畫面）")],
                             context_pct: d.context, starred: d.starred)
    }

    func reply(_ id: String, text: String) throws {
        let i = try index(id)
        append(i, "user", text)
        work(i, activity: String(localized: "思考中"),
             finish: String(localized: "（展示模式）收到：「\(text)」。連上自己的筆電之後，這裡會是 Claude 真正的回覆。"))
    }

    func key(_ id: String, _ key: String, label: String?) throws {
        let i = try index(id)
        guard let p = items[i].prompt else { return }
        // 方向鍵只移游標
        if key == "up" || key == "down" {
            let keys = p.options.map(\.key)
            let cur = keys.firstIndex(of: p.selected ?? "") ?? 0
            let next = max(0, min(keys.count - 1, cur + (key == "up" ? -1 : 1)))
            items[i].prompt = Prompt(options: p.options, selected: keys[next], type_key: p.type_key,
                                     submit_key: p.submit_key, review: p.review)
            changed()
            return
        }
        if key == "esc" {
            append(i, "system", String(localized: "已取消"))
            items[i].pending = nil
            items[i].prompt = nil
            items[i].awaiting = nil
            items[i].status = "idle"
            changed()
            return
        }
        let pick = key == "enter" ? p.selected : key
        guard let o = p.options.first(where: { $0.key == pick }) else { return }
        if label != nil && label != o.label { throw APIError(message: String(localized: "畫面已經變了，重新整理再按")) }
        if items[i].pending?.kind == "ask" {
            if o.key == p.type_key { return }   // 「Type something」要從下面的輸入框打字
            append(i, "user", String(localized: "選了：\(o.label)"))
            work(i, activity: String(localized: "部署中"), finish: String(localized: "（展示模式）照你選的「\(o.label)」部署好了，網址是 https://shop.example.com。"))
        } else if o.label.hasPrefix("No") {
            append(i, "system", String(localized: "沒有允許，Claude 停下來等你說要怎麼做"))
            items[i].pending = nil
            items[i].prompt = nil
            items[i].awaiting = nil
            items[i].status = "idle"
            changed()
        } else {
            work(i, activity: String(localized: "Bash：npm test"),
                 finish: String(localized: "（展示模式）測試全過（42 passed）。登入逾時修好了：有效時間改回 30 分鐘。"))
        }
    }

    func interrupt(_ id: String) throws {
        let i = try index(id)
        items[i].status = "idle"
        items[i].activity = ""
        items[i].pending = nil
        items[i].prompt = nil
        items[i].awaiting = nil
        append(i, "system", String(localized: "已中斷"))
        changed()
    }

    func close(_ id: String) throws {
        items.remove(at: try index(id))
        changed()
    }

    func star(_ id: String, _ on: Bool) throws {
        items[try index(id)].starred = on
        changed()
    }

    func settings() -> API.ServerSettings { API.ServerSettings(star_only_push: starOnly, done_push: donePush) }

    func setDonePush(_ on: Bool) -> API.ServerSettings {
        donePush = on
        return settings()
    }

    func setStarOnlyPush(_ on: Bool) -> API.ServerSettings {
        starOnly = on
        return settings()
    }

    func quota() -> Quota {
        let soon = Self.iso(Date().addingTimeInterval(3 * 3600)), week = Self.iso(Date().addingTimeInterval(70 * 3600))
        return Quota(accounts: [
            QuotaAccount(id: "claude-work", account: "work", vendor: "claude", label: "work", weekly_pct: 42,
                         weekly_resets: week, short_pct: 12, short_resets: soon, stale: false, blocked: false),
            QuotaAccount(id: "claude-personal", account: "personal", vendor: "claude", label: "personal", weekly_pct: 8,
                         weekly_resets: week, short_pct: 0, short_resets: soon, stale: false, blocked: false),
        ], generated_at: Self.iso(Date()))
    }

    func options() -> Options {
        Options(projects: ["~/Projects/shop", "~/Projects/api", "~/Projects/atlas", "~/Projects/notes", "~/Projects/blog"],
                recent: ["~/Projects/shop", "~/Projects/api"],
                accounts: [Account(id: "work", label: "work"), Account(id: "personal", label: "personal")])
    }

    func newSession(directory: String, account: String, prompt: String) -> String {
        let id = nextID("demo-new")
        let project = (directory as NSString).lastPathComponent
        items.insert(Demo(id: id, name: project, cwd: directory, account: account, status: "idle", since: Date(),
                          messages: [], context: 0), at: 0)
        if !prompt.isEmpty {
            append(0, "user", prompt)
            work(0, activity: String(localized: "思考中"), finish: String(localized: "（展示模式）新 session 開好了。連上自己的筆電之後，這裡會在筆電的 iTerm2 開一個真的 Claude Code。"))
        } else {
            changed()
        }
        return id
    }

    func toolDetail(_ id: String, message: String) throws -> ToolDetail {
        let d = items[try index(id)]
        guard let m = d.messages.first(where: { $0.id == message }) ?? (d.awaiting?.id == message ? d.awaiting : nil) else {
            throw APIError(message: String(localized: "找不到這個工具呼叫"))
        }
        let tool = m.tool ?? "Tool"
        let input: [String: JSONValue] = tool == "Bash" ? ["command": .string(m.text)] : ["file_path": .string(m.text)]
        let waiting = d.awaiting?.id == m.id
        return ToolDetail(tool: tool, summary: m.text, input: input,
                          output: waiting ? nil : String(localized: "（展示模式的假輸出）"), output_truncated: false, is_error: false)
    }

    func search(_ id: String, query: String) throws -> [SearchHit] {
        let q = query.lowercased()
        return items[try index(id)].messages
            .filter { $0.text.lowercased().contains(q) }
            .map { SearchHit(id: $0.id, role: $0.role, tool: $0.tool, snippet: $0.text) }
    }

    /// 照片不上傳，回一個假路徑讓畫面照常走
    func upload(_ id: String) throws -> String {
        _ = try index(id)
        return "~/Projects/.session-remote/uploads/demo-photo.jpg"
    }
}
