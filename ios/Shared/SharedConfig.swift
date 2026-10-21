import Foundation
import ActivityKit

/// app 與小工具共用的東西：連線設定放在 App Group 裡（小工具自己打筆電的 API），
/// 以及即時狀態（Live Activity）的資料形狀。
enum SharedConfig {
    static let group = "group.com.bruuucechang.sessionremote"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func save(url: String, token: String) {
        defaults.set(url, forKey: "serverURL")
        defaults.set(token, forKey: "token")
    }

    static var api: API? {
        guard let u = defaults.string(forKey: "serverURL"), let url = URL(string: u),
              let t = defaults.string(forKey: "token"), !t.isEmpty else { return nil }
        return API(base: url, token: t)
    }
}

/// 欄位名要跟筆電 backend/app/services/notify.py 的 activity_payload 的 content-state 一字不差，
/// 不然推播來的更新解不開、畫面停在舊的。
struct SessionsActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var working: Int
        var waiting: Int
        var done: Int
        var headline: String
    }
}

extension SessionSummary {
    /// 「專案｜摘要」的專案那段
    var project: String { name.components(separatedBy: "｜").first ?? name }
}

enum Summary {
    static func state(_ sessions: [SessionSummary]) -> SessionsActivityAttributes.ContentState {
        let waiting = sessions.filter { $0.status == "waiting" }
        let working = sessions.filter { $0.status == "working" }
        let headline: String
        if let w = waiting.first {
            headline = "\(w.project)：\(w.pending?.headline ?? "等你回答")"
        } else if let w = working.first {
            headline = "\(w.project)：\(w.activity.isEmpty ? "工作中" : w.activity)"
        } else {
            headline = "都做完了"
        }
        return .init(working: working.count, waiting: waiting.count,
                     done: sessions.filter { $0.status == "done" }.count, headline: String(headline.prefix(120)))
    }
}
