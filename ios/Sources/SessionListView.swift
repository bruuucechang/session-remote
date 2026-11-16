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
    /// 關分頁／標星號失敗的原因，顯示在出事的那一列（key 是 session id）
    @State private var rowErrors: [String: String] = [:]

    /// 依狀態分組，要你處理的排最上面
    private static let order: [(key: String, title: String)] = [
        ("starred", "星號"), ("waiting", "等你回答"), ("working", "工作中"), ("background", "背景跑"), ("done", "完工"), ("idle", "待命"), ("", "其他"),
    ]

    private var sections: [(title: String, items: [SessionSummary])] {
        let known = Set(Self.order.map(\.key).filter { !$0.isEmpty && $0 != "starred" })
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = q.isEmpty ? store.sessions : store.sessions.filter {
            ($0.name + " " + $0.cwd + " " + ($0.account.id ?? "")).lowercased().contains(q)
        }
        return Self.order.compactMap { o in
            // 標了星號的不管狀態都放最上面那一區，其他區不再重複出現
            let items = o.key == "starred"
                ? pool.filter { $0.starred == true }
                : pool.filter { $0.starred != true && (o.key.isEmpty ? !known.contains($0.status) : $0.status == o.key) }
            return items.isEmpty ? nil : (o.title, items)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.isDemo {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("展示模式", systemImage: "sparkles.tv")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.tint)
                            Text("下面是 app 內建的假資料，按什麼都不會連網。點「等你回答」的 session 試著回答看看。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("退出展示模式") { store.exitDemo() }
                    }
                }
                // 連不上但手上還有上次的列表：留著列表，上面講清楚這是舊的
                if let err = store.error, !store.sessions.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("連不上筆電，下面是上次的資料", systemImage: "wifi.exclamationmark")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(err).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("再試一次") { Task { await store.refresh() } }
                    }
                }
                // 要你處理的（星號、等你回答）在最上面，額度卡接在後面
                let urgent = Self.urgent
                ForEach(sections.filter { urgent.contains($0.title) }, id: \.title) { section($0) }
                if !store.quota.isEmpty && query.isEmpty {
                    Section {
                        QuotaCard(accounts: store.quota)
                    }
                }
                ForEach(sections.filter { !urgent.contains($0.title) }, id: \.title) { section($0) }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !store.loaded {
                    ProgressView("連到筆電…")
                } else if store.sessions.isEmpty, let err = store.error {

                    ContentUnavailableView {
                        Label("連不上筆電", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("\(err)。確認筆電開著、session-remote 服務在跑、手機連著 Tailscale。")
                    } actions: {
                        Button("再試一次") { Task { await store.refresh() } }
                            .buttonStyle(.borderedProminent)
                        Button("檢查設定") { showSettings = true }
                    }
                } else if !query.isEmpty && sections.isEmpty {
                    ContentUnavailableView("找不到「\(query)」", systemImage: "magnifyingglass",
                                           description: Text("專案名稱、資料夾、帳號都沒有這幾個字。"))
                } else if store.sessions.isEmpty {
                    ContentUnavailableView {
                        Label("沒有 session", systemImage: "terminal")
                    } description: {
                        Text("筆電的 iTerm2 裡還沒有跑 Claude Code。")
                    } actions: {
                        Button("開新 session") { showNew = true }
                            .buttonStyle(.borderedProminent)
                    }
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
                        do { try await api.close(s.id); rowErrors[s.id] = nil }
                        catch { rowErrors[s.id] = "關不掉：\(error.localizedDescription)" }
                        await store.refresh()
                    }
                }
            } message: {
                Text("筆電上那個 iTerm2 分頁會關掉，對話紀錄還在，之後可以用 claude --resume 接回。")
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(firstRun: false) }
            }
            // 列表更新過（筆電那邊有變化）就把列上的舊錯誤清掉，不然網路恢復了還一直掛著
            .onChange(of: store.tick) { rowErrors = [:] }
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

extension SessionListView {
    static let urgent: Set<String> = ["星號", "等你回答"]

    @ViewBuilder
    private func section(_ sec: (title: String, items: [SessionSummary])) -> some View {
        // 搜尋時不收起，找到的就要看得到
        let foldable = sec.title == "待命" && query.isEmpty
        Section {
            if !foldable || idleExpanded {
                ForEach(sec.items) { s in
                    NavigationLink(value: s.id) { SessionRow(s: s, error: rowErrors[s.id]) }
                        .swipeActions(edge: .leading) {
                            Button { toggleStar(s) } label: {
                                Label(s.starred == true ? "取消星號" : "標星號",
                                      systemImage: s.starred == true ? "star.slash" : "star.fill")
                            }
                            .tint(.yellow)
                        }
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
            } else if sec.title == "星號" {
                Label("\(sec.title) · \(sec.items.count)", systemImage: "star.fill")
            } else {
                Text("\(sec.title) · \(sec.items.count)")
            }
        }
    }

    func toggleStar(_ s: SessionSummary) {
        guard let api = store.api else { return }
        Task {
            do { try await api.star(s.id, s.starred != true); rowErrors[s.id] = nil }
            catch { rowErrors[s.id] = "星號沒改到：\(error.localizedDescription)" }
            await store.refresh()
        }
    }
}

struct SessionRow: View {
    let s: SessionSummary
    var error: String? = nil

    var body: some View {
        let name = SessionName(s.name)
        HStack(alignment: .top, spacing: 12) {
            StatusBadge(status: s.status)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if s.starred == true {
                        Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    }
                    Text(name.project).font(.body.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let since = s.status_since.flatMap(parseDate) {
                        Text(Self.when(s.status, since)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                HStack(spacing: 6) {
                    AccountChip(account: s.account)
                    if let ctx = s.context_pct {
                        ContextChip(pct: ctx)
                    }
                    // 等你回答的同時背景也在跑：狀態照舊，多一個小標
                    if s.status != "background", let bg = s.background, !bg.isEmpty {
                        Label("背景 \(bg.count)", systemImage: "hourglass")
                            .font(.caption2.weight(.semibold)).foregroundStyle(.purple)
                            .labelStyle(.titleAndIcon)
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
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var preview: (text: String, color: Color)? {
        if s.status == "waiting", let p = s.pending { return (p.headline, .orange) }
        if s.status == "working", !s.activity.isEmpty { return (s.activity, .secondary) }
        if s.status == "background", let bg = s.background, let first = bg.first {
            return ("背景：" + first + (bg.count > 1 ? "（共 \(bg.count) 件）" : ""), .purple)
        }
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

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant_TW")
        f.dateFormat = "M/d HH:mm"
        return f
    }()

    /// 一小時內講「幾分鐘前」，再久就講幾點（「6 小時前」看不出是今天早上還是昨晚）；完工的加上「完工」（背景也跑完的時間）
    static func when(_ status: String, _ d: Date, now: Date = Date()) -> String {
        let t: String
        if now.timeIntervalSince(d) < 3600 {
            t = ago(d, now: now)
        } else if Calendar.current.isDate(d, inSameDayAs: now) {
            t = "今天 " + clock.string(from: d)
        } else if let y = Calendar.current.date(byAdding: .day, value: -1, to: now), Calendar.current.isDate(d, inSameDayAs: y) {
            t = "昨天 " + clock.string(from: d)
        } else {
            t = day.string(from: d)
        }
        return status == "done" ? t + " 完工" : t
    }

    static func ago(_ d: Date, now: Date = Date()) -> String {
        now.timeIntervalSince(d) < 60 ? "剛剛" : agoFormatter.localizedString(for: d, relativeTo: now)
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
        case "background": return "hourglass"
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
