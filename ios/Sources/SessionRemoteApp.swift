import SwiftUI
import UserNotifications

@main
struct SessionRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear { delegate.store = store }
                .onOpenURL { store.handle(url: $0) }
                .onChange(of: phase) { _, p in
                    if p == .active {
                        Task { await store.refresh() }
                        store.start()
                    } else if p == .background {
                        store.stop()
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SR_PREVIEW"] == "widgets" {
            WidgetPreviewPage()
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder private var main: some View {
        if store.isConfigured {
            SessionListView()
        } else {
            NavigationStack { SettingsView(firstRun: true) }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var store: Store?

    func application(_ app: UIApplication, didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        #if DEBUG
        // 模擬器驗收（見 Store.init）時不要跳推播權限框，會蓋住截圖
        if ProcessInfo.processInfo.environment["SR_URL"] != nil { return true }
        #endif
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { app.registerForRemoteNotifications() }
        }
        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in self.store?.didRegisterPush(token: hex) }
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("推播註冊失敗：\(error)")
    }

    // app 開著的時候也顯示通知橫幅
    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // 點通知 → 打開那個 session
    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if let sid = response.notification.request.content.userInfo["session"] as? String {
            await MainActor.run { self.store?.openSession = sid }
        }
    }
}

#if DEBUG
/// 模擬器驗收：SR_PREVIEW=widgets 開一頁把小工具與鎖定畫面的樣子畫出來（無頭模擬器擺不了小工具、鎖不了螢幕）
struct WidgetPreviewPage: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let entry = WaitingEntry(date: .now, sessions: store.sessions, error: nil)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("小工具").font(.headline)
                HStack(spacing: 16) {
                    tile(WaitingWidgetView(entry: entry, familyOverride: .systemSmall), 170, 170)
                    tile(WaitingWidgetView(entry: entry, familyOverride: .accessoryCircular), 76, 76)
                }
                tile(WaitingWidgetView(entry: entry, familyOverride: .systemMedium), 364, 170)
                tile(WaitingWidgetView(entry: entry, familyOverride: .accessoryRectangular), 172, 76)
                Text("鎖定畫面即時狀態").font(.headline)
                LockScreenView(state: Summary.state(store.sessions))
                    .padding(14)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 22))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task { await store.refresh() }
    }

    private func tile<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat) -> some View {
        v.padding(14)
            .frame(width: w, height: h)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
}
#endif
