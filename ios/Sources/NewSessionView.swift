import SwiftUI

struct NewSessionView: View {
    let onCreated: (String) -> Void
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var options: Options?
    @State private var account = ""
    @State private var query = ""
    @State private var error: String?
    @State private var busy = false
    /// 第一句話：填了 Claude 一開起來就照著做
    @State private var prompt = ""
    /// 選好的資料夾；按右上角「開始」才真的開（以前點資料夾就開，填完第一句話找不到送出鈕）
    @State private var directory: String?

    var body: some View {
        NavigationStack {
            List {
                if let err = error {
                    Text(err).foregroundStyle(.red).font(.footnote)
                }
                if let o = options {
                    Section("帳號") {
                        Picker("帳號", selection: $account) {
                            ForEach(o.accounts, id: \.id) { a in
                                Text(a.id ?? a.label ?? "").tag(a.id ?? "")
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section {
                        TextField("例如：跑測試，紅的修好", text: $prompt, axis: .vertical)
                            .lineLimit(1...4)
                    } header: {
                        Text("第一句話（可不填）")
                    } footer: {
                        Text("填了的話，Claude 一開起來就照著做；不填就開好等你。")
                    }
                    Section("資料夾") {
                        if let dir = directory {
                            Label(shortPath(dir), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        } else {
                            Text("從下面選一個，再按右上角「開始」").foregroundStyle(.secondary)
                        }
                    }
                    let recent = filtered(o.recent ?? [])
                    if !recent.isEmpty {
                        Section("最近用過") {
                            ForEach(recent, id: \.self) { folderRow($0, icon: "clock.arrow.circlepath") }
                        }
                    }
                    Section("全部資料夾") {
                        ForEach(filtered(o.projects), id: \.self) { folderRow($0, icon: "folder") }
                    }
                } else if error == nil {
                    ProgressView()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .searchable(text: $query, prompt: "找資料夾")
            .navigationTitle("開新 session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("開始") { if let d = directory { create(d) } }
                        .disabled(busy || account.isEmpty || directory == nil)
                }
            }
            .overlay { if busy { ProgressView("在筆電開分頁…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { await load() }
        }
    }

    private func folderRow(_ dir: String, icon: String) -> some View {
        Button {
            directory = dir
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text((dir as NSString).lastPathComponent)
                    // lanes 底下的子資料夾要看得出是哪個專案的
                    let parent = ((dir as NSString).deletingLastPathComponent as NSString).lastPathComponent
                    if parent != "Projects" {
                        Text(parent).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if directory == dir {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .disabled(busy)
    }

    /// /Users/<名字>/Projects/x → ~/Projects/x（路徑是筆電的，不能用手機的 NSHomeDirectory）
    private func shortPath(_ dir: String) -> String {
        let parts = dir.split(separator: "/")
        guard dir.hasPrefix("/Users/"), parts.count > 2 else { return dir }
        return "~/" + parts.dropFirst(2).joined(separator: "/")
    }

    private func filtered(_ dirs: [String]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? dirs : dirs.filter { $0.lowercased().contains(q) }
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            let o = try await api.options()
            options = o
            if account.isEmpty { account = o.accounts.first?.id ?? "" }
            #if DEBUG
            if let d = ProcessInfo.processInfo.environment["SR_DIR"] { directory = d }
            #endif
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func create(_ dir: String) {
        guard let api = store.api else { return }
        busy = true
        Task {
            do {
                let id = try await api.newSession(directory: dir, account: account, prompt: prompt)
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
