import ActivityKit
import Foundation

/// 鎖定畫面與動態島的即時狀態。
///
/// app 開著時自己更新；app 不在前景時由筆電推播更新（所以要把 Activity 的推播 token 報給筆電）。
/// 全部停下來就結束（留 15 分鐘再消失）。iOS 17.2 起還有「遠端開啟」的 token：
/// app 沒開的時候有 session 開始工作，筆電也能把它叫出來。
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()
    private var api: API?
    private var observed = Set<String>()
    private var attached = false

    func attach(api: API) {
        self.api = api
        guard !attached else { return }
        attached = true
        for a in Activity<SessionsActivityAttributes>.activities { observe(a) }
        // 筆電遠端開的那一個也要拿到更新用的 token
        Task { for await a in Activity<SessionsActivityAttributes>.activityUpdates { observe(a) } }
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<SessionsActivityAttributes>.pushToStartTokenUpdates {
                    try? await self.api?.registerActivity(token: data.hex, kind: "start")
                }
            }
        }
    }

    func sync(_ sessions: [SessionSummary], api: API) {
        self.api = api
        #if DEBUG
        // 模擬器驗收時不要開（會跳權限框蓋住截圖）；SR_ACTIVITY=1 才開來看動態島
        let env = ProcessInfo.processInfo.environment
        if env["SR_URL"] != nil && env["SR_ACTIVITY"] != "1" { return }
        #endif
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = Summary.state(sessions)
        let active = state.working + state.waiting > 0
        let content = ActivityContent(state: state, staleDate: nil)
        // 結束後的那個還會留在 activities 裡（狀態 .ended，15 分鐘後才消失）：更新它沒有用，要找還活著的
        if let a = Activity<SessionsActivityAttributes>.activities.first(where: { $0.activityState == .active || $0.activityState == .stale }) {
            Task {
                if active {
                    await a.update(content)
                } else {
                    await a.end(content, dismissalPolicy: .after(.now.addingTimeInterval(15 * 60)))
                }
            }
        } else if active {
            if let a = try? Activity.request(attributes: SessionsActivityAttributes(), content: content, pushType: .token) {
                observe(a)
            }
        }
    }

    private func observe(_ a: Activity<SessionsActivityAttributes>) {
        guard !observed.contains(a.id) else { return }
        observed.insert(a.id)
        Task {
            for await data in a.pushTokenUpdates {
                try? await self.api?.registerActivity(token: data.hex, kind: "update")
            }
        }
    }
}

extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
