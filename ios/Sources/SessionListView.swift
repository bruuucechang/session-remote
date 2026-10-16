import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: Store
    @State private var path: [String] = []
    @State private var showNew = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let err = store.error {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                if store.sessions.isEmpty && store.error == nil {
                    ContentUnavailableView("沒有 session", systemImage: "terminal",
                                           description: Text("筆電的 iTerm2 裡還沒有跑 Claude Code。按右上角 ＋ 開一個。"))
                }
                ForEach(store.sessions) { s in
                    NavigationLink(value: s.id) { SessionRow(s: s) }
                }
            }
            .listStyle(.plain)
            .refreshable { await store.refresh() }
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(store.connected ? .green : .red).frame(width: 7, height: 7).offset(x: 4, y: -3)
                            }
                    }
                    .accessibilityLabel(store.connected ? "設定（已連線）" : "設定（未連線）")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("開新 session")
                }
            }
            .sheet(isPresented: $showNew) {
                NewSessionView { id in
                    showNew = false
                    Task {
                        // 新分頁的 claude 要幾秒才起得來
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        await store.refresh()
                        path = [id]
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(firstRun: false) }
            }
            .onChange(of: store.openSession) { _, sid in
                if let sid { path = [sid]; store.openSession = nil }
            }
            .task {
                await store.refresh()
                if let sid = store.openSession { path = [sid]; store.openSession = nil }
            }
        }
    }
}

struct SessionRow: View {
    let s: SessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(Status.color(s.status)).frame(width: 9, height: 9)
                Text(s.name).font(.headline).lineLimit(1)
                Spacer()
                Text(Status.label(s.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Status.color(s.status))
            }
            HStack(spacing: 6) {
                Text(s.account.label ?? s.account.id ?? "")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                if let since = s.status_since.flatMap(parseDate) {
                    Text(since, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if s.status == "waiting", let p = s.pending {
                Text(p.headline).font(.subheadline).foregroundStyle(.orange).lineLimit(2)
            } else if s.status == "working", !s.activity.isEmpty {
                Text(s.activity).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            } else if !s.last_text.isEmpty {
                Text(s.last_text).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseDate(_ s: String) -> Date? {
    isoFrac.date(from: s) ?? ISO8601DateFormatter().date(from: s)
}
