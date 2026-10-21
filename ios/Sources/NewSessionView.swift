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
            .searchable(text: $query, prompt: "找資料夾")
            .navigationTitle("開新 session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .overlay { if busy { ProgressView("在筆電開分頁…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .task { await load() }
        }
    }

    private func folderRow(_ dir: String, icon: String) -> some View {
        Button {
            create(dir)
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
            }
        }
        .disabled(busy || account.isEmpty)
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
