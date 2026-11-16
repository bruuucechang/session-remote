import Foundation
import SwiftUI
import UserNotifications
import WidgetKit

/// 全 app 共用的狀態：連線設定、session 列表、即時更新。
@MainActor
final class Store: ObservableObject {
    @Published var serverURL: String = UserDefaults.standard.string(forKey: "serverURL") ?? "http://100.72.62.85:5391"
    @Published var token: String = Keychain.get("token") ?? ""
    @Published var sessions: [SessionSummary] = []
    @Published var error: String?
    @Published var connected = false
    /// 第一次抓列表回來之前是 false：筆電第一次問 iTerm2 要好幾秒，不能把「還沒載入」顯示成「沒有 session」
    @Published var loaded = false
    /// 每次伺服器說「有東西變了」就 +1，詳細頁盯著它重抓
    @Published var tick = 0
    /// 點推播通知要打開的 session
    @Published var openSession: String?
    /// 兩個帳號的額度（列表最上面那一塊）
    @Published var quota: [QuotaAccount] = []
    private var quotaFetched = Date.distantPast
    /// 每個 session 還沒送出的草稿（切去別的 session 再回來字還在）
    private var drafts: [String: String] = UserDefaults.standard.dictionary(forKey: "drafts") as? [String: String] ?? [:]

    var pushToken: String?
    private var eventsTask: Task<Void, Never>?

    /// 模擬器驗收／UI 測試帶 SR_URL 連假資料後端時為 true：這時不准寫進 App Group，
    /// 不然真機跑完測試，手機上的小工具會指到假資料後端
    private var overridden = false

    /// 展示模式（配對頁的「先看看」）：資料全部來自 app 內建的假資料、不連網，也不存進手機。
    /// 不記住：重開 app 回到配對頁
    @Published private(set) var demo: DemoBackend?
    var isDemo: Bool { demo != nil }
    /// 測試模式或展示模式：不准動手機上的東西（App Group、紅點、即時狀態、推播註冊、草稿）
    private var sandboxed: Bool { overridden || demo != nil }

    init() {
        #if DEBUG
        // 模擬器驗收用：SIMCTL_CHILD_SR_URL／SR_TOKEN／SR_OPEN 從 simctl launch 帶進來，
        // 不用點畫面就能連上並打開某個 session（無頭模擬器沒辦法點）
        let env = ProcessInfo.processInfo.environment
        if let u = env["SR_URL"], let t = env["SR_TOKEN"] {
            serverURL = u
            token = t
            overridden = true
        }
        if let o = env["SR_OPEN"], !o.isEmpty { openSession = o }
        // UI 測試第一次配對：當成還沒設定過，但存的東西不寫進手機
        if env["SR_FIRSTRUN"] == "1" { token = ""; overridden = true }
        // 模擬器驗收展示模式：SR_DEMO=1 一打開就進展示模式
        if env["SR_DEMO"] == "1" { demo = DemoBackend() }
        #endif
    }

    func draft(_ id: String) -> String { drafts[id] ?? "" }

    func setDraft(_ id: String, _ text: String) {
        // 測試模式的草稿不寫進手機的設定（假資料的 session id 留在那裡只是垃圾）
        if sandboxed { return }
        if text.isEmpty { drafts[id] = nil } else { drafts[id] = text }
        UserDefaults.standard.set(drafts, forKey: "drafts")
    }

    var isConfigured: Bool { demo != nil || (!token.isEmpty && URL(string: serverURL) != nil) }

    var api: API? {
        if let demo { return API.demo(demo) }
        guard let url = URL(string: serverURL), !token.isEmpty else { return nil }
        return API(base: url, token: token)
    }

    func enterDemo() {
        stop()
        sessions = []
        quota = []
        quotaFetched = .distantPast
        loaded = false
        demo = DemoBackend()
        restart()
    }

    /// 退出展示模式：回到配對頁（或原本配對好的筆電）
    func exitDemo() {
        stop()
        demo = nil
        sessions = []
        quota = []
        quotaFetched = .distantPast
        loaded = false
        openSession = nil
        if isConfigured { restart() }
    }

    func save(serverURL: String, token: String) {
        // 在展示模式裡配對：直接換成真的筆電
        demo = nil
        self.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        self.token = token.trimmingCharacters(in: .whitespaces)
        if !overridden {
            UserDefaults.standard.set(self.serverURL, forKey: "serverURL")
            Keychain.set("token", self.token)
            SharedConfig.save(url: self.serverURL, token: self.token)
        }
        restart()
    }

    /// 先用這組網址與通行碼抓一次列表，連得上才存；回傳錯誤訊息（nil＝成功）
    func connect(serverURL: String, token: String) async -> String? {
        let u = serverURL.trimmingCharacters(in: .whitespaces), t = token.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: u), url.scheme != nil else { return "網址看不懂，要像 http://100.x.x.x:5391" }
        do {
            _ = try await API(base: url, token: t).sessions()
        } catch {
            return error.localizedDescription
        }
        save(serverURL: u, token: t)
        return nil
    }

    /// sessionremote://setup?url=...&token=...（筆電上 tools/pair.py 印的 QR code）
    /// sessionremote://open?id=...（小工具、鎖定畫面點進來）
    func handle(url: URL) {
        guard url.scheme == "sessionremote" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let get = { (n: String) in items.first { $0.name == n }?.value }
        switch url.host {
        case "setup":
            if let u = get("url"), let t = get("token") { save(serverURL: u, token: t) }
        case "open":
            if let id = get("id") { openSession = id }
        default:
            break
        }
    }

    func refresh() async {
        guard let api else { return }
        let source = demo
        do {
            let list = try await api.sessions().sessions
            // 抓的途中進出展示模式：這份是另一邊的資料，丟掉
            guard source === demo else { return }
            sessions = list
            #if DEBUG
            // 模擬器驗收：SR_HIDE=waiting,done 把這幾種藏起來，讓畫面下面的區塊（收起來的待命）擠得進一張截圖
            if let hide = ProcessInfo.processInfo.environment["SR_HIDE"]?.split(separator: ",").map(String.init) {
                sessions.removeAll { hide.contains($0.status) }
            }
            #endif
            error = nil
            loaded = true
            // app 圖示的紅點＝等你回答的數量（app 不在前景時由筆電推播的 badge 更新）
            let waiting = sessions.filter { $0.status == "waiting" }.count
            // 測試模式不動：假資料的數字會留在真機的 app 圖示上
            if !sandboxed { try? await UNUserNotificationCenter.current().setBadgeCount(waiting) }
            if demo == nil {
                LiveActivityController.shared.sync(sessions, api: api)
                WidgetCenter.shared.reloadAllTimelines()
            }
            if Date().timeIntervalSince(quotaFetched) > 60 {
                quotaFetched = Date()
                quota = (try? await api.quota().accounts) ?? quota
            }
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
    }

    func start() {
        // 舊版只存在 app 自己的設定裡：補一份到 App Group 給小工具用
        if isConfigured && !sandboxed { SharedConfig.save(url: serverURL, token: token) }
        if let api, !sandboxed { LiveActivityController.shared.attach(api: api) }
        guard eventsTask == nil else { return }
        eventsTask = Task { [weak self] in
            var delay: UInt64 = 1
            while !Task.isCancelled {
                guard let self, let api = self.api else { return }
                do {
                    try await api.events { [weak self] in
                        guard let self else { return }
                        self.connected = true
                        self.tick += 1
                        Task { await self.refresh() }
                    }
                    delay = 1
                } catch {
                    self.connected = false
                }
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                delay = min(delay * 2, 15)
            }
        }
        if let pushToken, demo == nil { Task { try? await api?.registerDevice(token: pushToken) } }
    }

    func stop() {
        eventsTask?.cancel()
        eventsTask = nil
        connected = false
    }

    func restart() {
        stop()
        Task { await refresh() }
        start()
    }

    func didRegisterPush(token: String) {
        pushToken = token
        Task { try? await api?.registerDevice(token: token) }
    }
}

/// 通行碼放 Keychain，不放 UserDefaults。
enum Keychain {
    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
}

enum Status {
    static func label(_ s: String) -> String {
        switch s {
        case "waiting": return "等你回答"
        case "working": return "工作中"
        case "background": return "背景跑"
        case "done": return "完工"
        case "idle": return "待命"
        default: return "未回報"
        }
    }

    static func color(_ s: String) -> Color {
        switch s {
        case "waiting": return .orange
        case "working": return .blue
        case "background": return .purple
        case "done": return .green
        default: return .gray
        }
    }
}
