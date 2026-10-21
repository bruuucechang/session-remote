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
                    Section("在哪個資料夾開") {
                        ForEach(filtered(o.projects), id: \.self) { dir in
                            Button {
                                create(dir)
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text((dir as NSString).lastPathComponent)
                                    Spacer()
                                }
                            }
                            .disabled(busy || account.isEmpty)
                        }
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
                let id = try await api.newSession(directory: dir, account: account)
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
