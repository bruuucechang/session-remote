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
            if store.isDemo && !firstRun {
                Section {
                    Button("退出展示模式", role: .destructive) {
                        store.exitDemo()
                        dismiss()
                    }
                } header: {
                    Text("展示模式")
                } footer: {
                    Text("現在看的是 app 內建的假資料，沒有連到任何筆電。要連自己的筆電，在上面填好網址與通行碼按「儲存並連線」。")
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
                // 沒改又連得上就不用按；連不上時同一組設定也能再試
                .disabled(busy || url.isEmpty || token.isEmpty || (!firstRun && !changed && store.error == nil))
            }
            if firstRun {
                Section {
                    Button("先看看（展示模式）") { store.enterDemo() }
                        // 配對連線還在跑時不准進：連線晚點成功會 save()、把人從展示模式踢回真的筆電
                        .disabled(busy)
                } footer: {
                    Text("還沒在筆電上裝 session-remote？先用 app 內建的假資料看看怎麼用：列表、對話、回答題目都能按，不會連網。之後在設定頁可以退出。")
                }
            }
            if let on = starOnly {
                Section {
                    Toggle("完工只推標星號的", isOn: Binding(
                        get: { on },
                        set: { v in
                            starOnly = v
                            Task { starOnly = (try? await store.api?.setStarOnlyPush(v))?.star_only_push ?? !v }
                        }))
                } header: {
                    Text("推播")
                } footer: {
                    Text("開了之後，沒標星號的 session 完工不跳通知；等你回答的照樣會跳。")
                }
            }
            if !firstRun {
                Section("狀態") {
                    // LabeledContent(value:) 收 String、不會自己翻
                    LabeledContent("即時更新", value: store.isDemo ? String(localized: "展示模式")
                                   : store.connected ? String(localized: "連線中") : String(localized: "未連線"))
                    LabeledContent("推播", value: store.pushToken == nil ? String(localized: "未註冊") : String(localized: "已註冊"))
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
        if err.contains("通行碼") || err == L("通行碼不對") {  // l10n:skip 比對後端的錯誤
            return String(localized: "在筆電上跑 tools/pair.py 重新掃 QR code，或照它印的通行碼重打")
        }
        return String(localized: "確認筆電開著、session-remote 服務在跑、手機連著 Tailscale；網址照 tools/pair.py 印的填")
    }
}
