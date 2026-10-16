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
