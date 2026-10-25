import SwiftUI

struct SettingsView: View {
    let firstRun: Bool
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var busy = false
    /// 上次按「儲存並連線」失敗的原因（nil＝沒失敗過或已經成功）
    @State private var failure: String?
    /// 筆電上的設定（nil＝還沒讀到）
    @State private var starOnly: Bool?

    private var changed: Bool { url != store.serverURL || token != store.token }

    var body: some View {
        Form {
            if firstRun {
                Section {
                    Text("在筆電上跑 `session-remote/tools/pair.py`，用相機掃它印出的 QR code 就會自動填好。也可以手動輸入。")
                        .font(.footnote)
                }
            }
            Section {
                LabeledContent("網址") {
                    TextField("http://100.x.x.x:5391", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("通行碼") {
                    SecureField("筆電 .env 裡的", text: $token)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("筆電服務")
            } footer: {
                if let failure {
                    // 錯誤放在出事的那一塊，並且講下一步怎麼做
                    Label {
                        Text("連不上：\(failure)。\(hint(failure))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    connect()
                } label: {
                    HStack {
                        Text("儲存並連線")
                        Spacer()
                        if busy { ProgressView() }
                    }
                }
                .disabled(busy || url.isEmpty || token.isEmpty || (!firstRun && !changed))
            }
            if let on = starOnly {
                Section {
                    Toggle("做完只推標星號的", isOn: Binding(
                        get: { on },
                        set: { v in
                            starOnly = v
                            Task { starOnly = (try? await store.api?.setStarOnlyPush(v))?.star_only_push ?? !v }
                        }))
                } header: {
                    Text("推播")
                } footer: {
                    Text("開了之後，沒標星號的 session 做完不跳通知；等你回答的照樣會跳。")
                }
            }
            if !firstRun {
                Section("狀態") {
                    LabeledContent("即時更新", value: store.connected ? "連線中" : "未連線")
                    LabeledContent("推播", value: store.pushToken == nil ? "未註冊" : "已註冊")
                }
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
        .task {
            if !firstRun { starOnly = (try? await store.api?.settings())?.star_only_push }
        }
    }

    /// 先試連，連得上才存：通行碼打錯時不會把好的設定蓋掉，第一次配對也不會跳進一個連不上的列表
    private func connect() {
        busy = true
        failure = nil
        Task {
            failure = await store.connect(serverURL: url, token: token)
            busy = false
            if failure == nil && !firstRun { dismiss() }
        }
    }

    private func hint(_ err: String) -> String {
        if err.contains("通行碼") {
            return "在筆電上跑 tools/pair.py 重新掃 QR code，或照它印的通行碼重打"
        }
        return "確認筆電開著、session-remote 服務在跑、手機連著 Tailscale；網址照 tools/pair.py 印的填"
    }
}
