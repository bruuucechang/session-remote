import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: Store
    @State private var path: [String] = []
    @State private var showNew = false
    @State private var showSettings = false
    /// 待命的 session 常常一堆，預設收起來
    @AppStorage("idleExpanded") private var idleExpanded = false

    /// 依狀態分組，要你處理的排最上面
    private static let order: [(key: String, title: String)] = [
        ("waiting", "等你回答"), ("working", "工作中"), ("done", "做完了"), ("idle", "待命"), ("", "其他"),
    ]

    private var sections: [(title: String, items: [SessionSummary])] {
        let known = Set(Self.order.map(\.key).filter { !$0.isEmpty })
        return Self.order.compactMap { o in
            let items = store.sessions.filter { o.key.isEmpty ? !known.contains($0.status) : $0.status == o.key }
            return items.isEmpty ? nil : (o.title, items)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let err = store.error {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                ForEach(sections, id: \.title) { sec in
                    let foldable = sec.title == "待命"
                    Section {
                        if !foldable || idleExpanded {
                            ForEach(sec.items) { s in
                                NavigationLink(value: s.id) { SessionRow(s: s) }
                            }
                        }
                    } header: {
                        if foldable {
                            Button {
                                withAnimation(.snappy) { idleExpanded.toggle() }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(sec.title) · \(sec.items.count)")
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .rotationEffect(.degrees(idleExpanded ? 90 : 0))
                                    Spacer()
                                    if !idleExpanded {
                                        Text(sec.items.map { SessionName($0.name).project }.uniqued().joined(separator: "、"))
                                            .lineLimit(1).truncationMode(.tail)
                                            .textCase(nil)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("\(sec.title) · \(sec.items.count)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !store.loaded {
                    ProgressView("連到筆電…")
                } else if store.sessions.isEmpty && store.error == nil {
                    ContentUnavailableView("沒有 session", systemImage: "terminal",
                                           description: Text("筆電的 iTerm2 裡還沒有跑 Claude Code。按右上角 ＋ 開一個。"))
                }
            }
            .refreshable { await store.refresh() }
            .navigationTitle("Sessions")
            .navigationDestination(for: String.self) { SessionDetailView(sessionID: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        // 燈號放在圖示旁邊而不是疊在角落：iOS 26 的玻璃按鈕會把超出圖示的 overlay 裁掉
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                            Circle().fill(store.connected ? .green : .red).frame(width: 8, height: 8)
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
        let name = SessionName(s.name)
        HStack(alignment: .top, spacing: 12) {
            StatusBadge(status: s.status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(name.project).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let since = s.status_since.flatMap(parseDate) {
                        Text(Self.ago(since)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    AccountChip(account: s.account)
                    if let summary = name.summary {
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let preview {
                    Text(preview.text)
                        .font(.subheadline)
                        .foregroundStyle(preview.color)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: (text: String, color: Color)? {
        if s.status == "waiting", let p = s.pending { return (p.headline, .orange) }
        if s.status == "working", !s.activity.isEmpty { return (s.activity, .secondary) }
        if !s.last_text.isEmpty { return (Self.plain(s.last_text), .secondary) }
        return nil
    }

    /// 列表預覽不需要 Markdown 符號
    private static func plain(_ s: String) -> String {
        s.replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static let agoFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        f.locale = Locale(identifier: "zh_Hant_TW")
        return f
    }()

    static func ago(_ d: Date) -> String {
        Date().timeIntervalSince(d) < 60 ? "剛剛" : agoFormatter.localizedString(for: d, relativeTo: Date())
    }
}

/// 帳號標籤：只留「·」前面那段，兩個帳號各一個顏色，一眼分得出是誰的額度
struct AccountChip: View {
    let account: Account

    var body: some View {
        let full = account.label ?? account.id ?? ""
        let short = full.components(separatedBy: " · ").first ?? full
        Text(short)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        let palette: [Color] = [.indigo, .teal, .pink, .brown]
        let key = account.id ?? ""
        let h = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[h % palette.count]
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        ZStack {
            Circle().fill(Status.color(status).opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Status.color(status))
        }
        .frame(width: 32, height: 32)
    }

    private var symbol: String {
        switch status {
        case "waiting": return "questionmark"
        case "working": return "ellipsis"
        case "done": return "checkmark"
        case "idle": return "moon.zzz.fill"
        default: return "circle.dotted"
        }
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
