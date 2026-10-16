import SwiftUI

struct SettingsView: View {
    let firstRun: Bool
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var testResult: String?

    var body: some View {
        Form {
            if firstRun {
                Section {
                    Text("在筆電上跑 `session-remote/tools/pair.py`，用相機掃它印出的 QR code 就會自動填好。也可以手動輸入。")
                        .font(.footnote)
                }
            }
            Section("筆電服務") {
                TextField("網址", text: $url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("通行碼", text: $token)
            }
            Section {
                Button("儲存並連線") {
                    store.save(serverURL: url, token: token)
                    Task {
                        await store.refresh()
                        testResult = store.error ?? "連上了，看到 \(store.sessions.count) 個 session"
                        if store.error == nil && !firstRun { dismiss() }
                    }
                }
                .disabled(url.isEmpty || token.isEmpty)
                if let r = testResult { Text(r).font(.footnote) }
            }
            Section("狀態") {
                LabeledContent("即時更新", value: store.connected ? "連線中" : "未連線")
                LabeledContent("推播", value: store.pushToken == nil ? "未註冊" : "已註冊")
            }
        }
        .navigationTitle(firstRun ? "連到筆電" : "設定")
        .toolbar {
            if !firstRun {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .onAppear {
            url = store.serverURL
            token = store.token
        }
    }
}
