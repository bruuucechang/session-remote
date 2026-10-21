import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var store: Store
    @State private var path: [String] = []
    @State private var showNew = false
    @State private var showSettings = false
    /// 待命的 session 常常一堆，預設收起來
    @AppStorage("idleExpanded") private var idleExpanded = false
    @State private var closing: SessionSummary?
    @State private var query = ""
    @State private var closeError: String?

    /// 依狀態分組，要你處理的排最上面
    private static let order: [(key: String, title: String)] = [
        ("waiting", "等你回答"), ("working", "工作中"), ("done", "做完了"), ("idle", "待命"), ("", "其他"),
    ]

    private var sections: [(title: String, items: [SessionSummary])] {
        let known = Set(Self.order.map(\.key).filter { !$0.isEmpty })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = q.isEmpty ? store.sessions : store.sessions.filter {
            ($0.name + " " + $0.cwd + " " + ($0.account.id ?? "")).lowercased().contains(q)
        }
        return Self.order.compactMap { o in
            let items = pool.filter { o.key.isEmpty ? !known.contains($0.status) : $0.status == o.key }
            return items.isEmpty ? nil : (o.title, items)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let err = store.error ?? closeError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
                if !store.quota.isEmpty {
                    Section {
                        QuotaCard(accounts: store.quota)
                    }
                }
                ForEach(sections, id: \.title) { sec in
                    // 搜尋時不收起，找到的就要看得到
                    let foldable = sec.title == "待命" && query.isEmpty
                    Section {
                        if !foldable || idleExpanded {
                            ForEach(sec.items) { s in
                                NavigationLink(value: s.id) { SessionRow(s: s) }
                                    .swipeActions(edge: .trailing) {
                                        Button { closing = s } label: { Label("關掉", systemImage: "xmark.circle") }
                                            .tint(.red)
                                    }
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
            .searchable(text: $query, prompt: "找專案或帳號")
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
            .confirmationDialog(
                "關掉「\(closing.map { SessionName($0.name).project } ?? "")」？",
                isPresented: Binding(get: { closing != nil }, set: { if !$0 { closing = nil } }),
                titleVisibility: .visible
            ) {
                Button("結束 Claude 並關掉分頁", role: .destructive) {
                    guard let s = closing, let api = store.api else { return }
                    Task {
                        do { try await api.close(s.id); closeError = nil } catch { closeError = error.localizedDescription }
                        await store.refresh()
                    }
                }
            } message: {
                Text("筆電上那個 iTerm2 分頁會關掉，對話紀錄還在，之後可以用 claude --resume 接回。")
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(firstRun: false) }
            }
            .onChange(of: store.openSession) { _, sid in
                if let sid { path = [sid]; store.openSession = nil }
            }
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.environment["SR_NEW"] == "1" { showNew = true }
                #endif
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
                    if let ctx = s.context_pct {
                        ContextChip(pct: ctx)
                    }
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

    /// 「3 小時後」「2 天後」
    static func until(_ d: Date) -> String {
        agoFormatter.localizedString(for: d, relativeTo: Date())
    }

    static func ago(_ d: Date) -> String {
        Date().timeIntervalSince(d) < 60 ? "剛剛" : agoFormatter.localizedString(for: d, relativeTo: Date())
    }
}

/// 這個 session 用了多少 context：60% 變黃、80% 變紅（跟筆電狀態列同一條線，該寫交接單了）
struct ContextChip: View {
    let pct: Int

    var body: some View {
        Text("ctx \(pct)%")
            .font(.caption2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(pct >= 80 ? .red : pct >= 60 ? .orange : .secondary)
    }
}

/// 兩個帳號的額度：本週與 5 小時兩條，重置時間寫在旁邊
struct QuotaCard: View {
    let accounts: [QuotaAccount]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(accounts) { a in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.vendor == "codex" ? "Codex" : "Claude")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(a.vendor == "codex" ? Color.primary : Color(red: 0.85, green: 0.47, blue: 0.34))
                        AccountChip(account: Account(id: a.account, label: a.label))
                    }
                    .frame(width: 70, alignment: .leading)
                    if a.weekly_pct == nil && a.short_pct == nil {
                        Text("沒有資料").font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        bar("本週", a.weekly_pct, a.weekly_resets)
                        bar("5 小時", a.short_pct, a.short_resets)
                    }
                }
                .opacity(a.stale ? 0.5 : 1)
            }
        }
        .padding(.vertical, 2)
    }

    private func bar(_ title: String, _ pct: Int?, _ resets: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(title).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(pct.map { "\($0)%" } ?? "—").fontWeight(.semibold).monospacedDigit()
                    .foregroundStyle(color(pct))
            }
            .font(.caption2)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule().fill(color(pct)).frame(width: g.size.width * CGFloat(min(pct ?? 0, 100)) / 100)
                }
            }
            .frame(height: 5)
            if let r = resets.flatMap(parseDate) {
                Text("\(SessionRow.until(r))重置").font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func color(_ pct: Int?) -> Color {
        guard let p = pct else { return .gray }
        return p >= 90 ? .red : p >= 70 ? .orange : .green
    }
}

/// 帳號標籤：兩個帳號各一個顏色，一眼分得出是誰的額度
struct AccountChip: View {
    let account: Account

    var body: some View {
        // 顯示帳號名（bruce／peter），不顯示方案暱稱（98154／rakucamp）
        Text(account.id ?? account.label ?? "")
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
