import Foundation
import SwiftUI
import UserNotifications

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

    var pushToken: String?
    private var eventsTask: Task<Void, Never>?

    init() {
        #if DEBUG
        // 模擬器驗收用：SIMCTL_CHILD_SR_URL／SR_TOKEN／SR_OPEN 從 simctl launch 帶進來，
        // 不用點畫面就能連上並打開某個 session（無頭模擬器沒辦法點）
        let env = ProcessInfo.processInfo.environment
        if let u = env["SR_URL"], let t = env["SR_TOKEN"] {
            serverURL = u
            token = t
        }
        if let o = env["SR_OPEN"], !o.isEmpty { openSession = o }
        #endif
    }

    var isConfigured: Bool { !token.isEmpty && URL(string: serverURL) != nil }

    var api: API? {
        guard let url = URL(string: serverURL), !token.isEmpty else { return nil }
        return API(base: url, token: token)
    }

    func save(serverURL: String, token: String) {
        self.serverURL = serverURL.trimmingCharacters(in: .whitespaces)
        self.token = token.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(self.serverURL, forKey: "serverURL")
        Keychain.set("token", self.token)
        restart()
    }

    /// sessionremote://setup?url=...&token=...（筆電上 tools/pair.py 印的 QR code）
    func handle(url: URL) {
        guard url.scheme == "sessionremote", url.host == "setup",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        let get = { (n: String) in items.first { $0.name == n }?.value }
        if let u = get("url"), let t = get("token") { save(serverURL: u, token: t) }
    }

    func refresh() async {
        guard let api else { return }
        do {
            sessions = try await api.sessions().sessions
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
            try? await UNUserNotificationCenter.current().setBadgeCount(waiting)
        } catch is CancellationError {
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
    }

    func start() {
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
        if let pushToken { Task { try? await api?.registerDevice(token: pushToken) } }
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
        case "done": return "做完了"
        case "idle": return "待命"
        default: return "未回報"
        }
    }

    static func color(_ s: String) -> Color {
        switch s {
        case "waiting": return .orange
        case "working": return .blue
        case "done": return .green
        default: return .gray
        }
    }
}
