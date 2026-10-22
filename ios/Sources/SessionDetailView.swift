import PhotosUI
import SwiftUI

struct SessionDetailView: View {
    let sessionID: String
    @EnvironmentObject var store: Store
    @State private var detail: SessionDetail?
    /// 對話串自己留一份，之後只抓新增的接上去
    @State private var messages: [Message] = []
    @State private var hasMore = false
    @State private var loadingOlder = false
    @State private var error: String?
    @State private var text = ""
    @State private var sending = false
    @State private var showKeys = false
    @State private var showScreen = false
    @FocusState private var inputFocused: Bool
    @State private var optionsHeight: CGFloat = 0
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var confirmClose = false
    @State private var openTool: Message?
    @State private var showSearch = false
    /// 搜尋點了某一則：捲過去（還沒載入的先往前載）
    @State private var scrollTarget: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    Color.clear.frame(height: 1).id("top")
                    if hasMore {
                        Button {
                            Task { await loadOlder(proxy) }
                        } label: {
                            HStack(spacing: 6) {
                                if loadingOlder { ProgressView().controlSize(.mini) }
                                Text("載入更早的訊息")
                            }
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .disabled(loadingOlder)
                    }
                    if detail == nil && error == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(ChatItem.group(messages)) { item in
                        switch item {
                        case .message(let m): MessageView(m: m)
                        case .tools(let ms): ToolGroupView(tools: ms) { openTool = $0 }
                        }
                    }
                    if showScreen, let screen = detail?.screen, !screen.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(screen.joined(separator: "\n"))
                                .font(.system(size: 10, design: .monospaced))
                                .fixedSize()
                                .padding(10)
                        }
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            // 內容短的時候貼著底部（像聊天 app），不要上面一坨、中間一大片空白
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            #if DEBUG
            // 模擬器驗收：SR_SCROLL=top 載入後捲到最上面（無頭模擬器沒辦法用手滑）
            .onChange(of: messages.count) { _, _ in
                if ProcessInfo.processInfo.environment["SR_SCROLL"] == "top" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo("top", anchor: .top) }
                }
            }
            #endif
            .onChange(of: scrollTarget) { _, id in
                guard let id, let item = ChatItem.group(messages).first(where: { $0.contains(id) }) else { return }
                withAnimation { proxy.scrollTo(item.id, anchor: .top) }
                scrollTarget = nil
            }
            .onChange(of: inputFocused) { _, f in
                if f { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        if detail?.starred == true {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                        }
                        Text(detail.map { SessionName($0.name).project } ?? "")
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                    if let d = detail {
                        HStack(spacing: 4) {
                            Circle().fill(Status.color(d.status)).frame(width: 6, height: 6)
                            Text("\(Status.label(d.status)) · \(d.account.id ?? d.account.label ?? "")"
                                 + (d.context_pct.map { " · ctx \($0)%" } ?? ""))
                        }
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    .accessibilityLabel("搜尋對話")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showScreen.toggle(); Task { await load() } } label: {
                        Label(showScreen ? "隱藏終端機畫面" : "顯示終端機畫面", systemImage: "terminal")
                    }
                    Button { showKeys.toggle() } label: {
                        Label(showKeys ? "隱藏按鍵列" : "顯示按鍵列", systemImage: "keyboard")
                    }
                    Button {
                        let on = detail?.starred != true
                        act { try await $0.star(sessionID, on) }
                    } label: {
                        Label(detail?.starred == true ? "取消星號" : "標星號",
                              systemImage: detail?.starred == true ? "star.slash" : "star")
                    }
                    Divider()
                    Button(role: .destructive) { confirmClose = true } label: {
                        Label("關掉這個 session", systemImage: "xmark.circle")
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        .sheet(item: $openTool) { ToolDetailView(sessionID: sessionID, message: $0) }
        .sheet(isPresented: $showSearch) {
            ConversationSearch(sessionID: sessionID) { id in
                showSearch = false
                Task { await jump(to: id) }
            }
        }
        .confirmationDialog("結束 Claude 並關掉筆電上的分頁？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("關掉", role: .destructive) {
                act {
                    try await $0.close(sessionID)
                    dismiss()
                }
            }
        } message: {
            Text("對話紀錄還在，之後可以用 claude --resume 接回。")
        }
        // .task(id:) 進畫面時也會跑一次，不用另外掛 .task
        .task(id: store.tick) { await load() }
        // 草稿跟著 session 存：切去別的 session 再回來字還在
        .onAppear { if text.isEmpty { text = store.draft(sessionID) } }
        .onChange(of: text) { _, t in store.setDraft(sessionID, t) }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await sendPhoto(item) }
        }
        #if DEBUG
        // 模擬器驗收：SR_DRAFT 預先填好輸入框（\n 換行）、SR_FOCUS=1 叫出鍵盤，看長文字會不會跑出框外
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let d = env["SR_DRAFT"], text.isEmpty { text = d.replacingOccurrences(of: "\\n", with: "\n") }
            if env["SR_FOCUS"] == "1" { inputFocused = true }
            if env["SR_SEARCH"] != nil { showSearch = true }
        }
        #endif
    }

    // MARK: 底部操作區

    @ViewBuilder private var controls: some View {
        VStack(spacing: 10) {
            if let err = error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(err).lineLimit(2)
                    Spacer()
                    Button { error = nil } label: { Image(systemName: "xmark") }
                }
                .font(.caption).foregroundStyle(.red)
            }
            if let d = detail {
                if let p = d.prompt {
                    promptView(d, p)
                } else if d.status == "working" {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(d.activity.isEmpty ? "工作中…" : d.activity)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Button(role: .destructive) { act { try await $0.interrupt(sessionID) } } label: {
                            Label("中斷", systemImage: "stop.fill").font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small).tint(.red)
                    }
                }
            }
            if showKeys { keyRow }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ZStack {
                        Circle().fill(Color(.secondarySystemBackground))
                        if uploading {
                            ProgressView()
                        } else {
                            Image(systemName: "photo").font(.body.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 38, height: 38)
                }
                .disabled(uploading)
                .accessibilityLabel("傳照片")
            Composer(
                text: $text,
                placeholder: detail?.prompt?.type_key != nil ? "或自己打一個答案…" : "回覆…",
                sending: sending,
                focus: $inputFocused
            ) {
                let t = text
                act { try await $0.reply(sessionID, text: t); text = "" }
            }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private func promptView(_ d: SessionDetail, _ p: Prompt) -> some View {
        let options = p.options.filter { $0.key != p.type_key && !$0.label.hasPrefix("Chat about") }
        let current = PromptMatch(pending: d.pending, prompt: p)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: d.pending?.kind == "ask" ? "questionmark.bubble.fill" : "hand.raised.fill")
                Text(p.review != nil ? "確認答案 · 共 \(p.review!.count) 題" : current.badge ?? "Claude 在等你")
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)

            Text(p.review != nil ? "要送出這幾題的答案嗎？" : current.title ?? d.pending?.headline ?? "Claude 在等你選")
                .font(.subheadline.weight(.semibold))
                // 打字的時候只留兩行，把位置讓給輸入框
                .lineLimit(inputFocused ? 2 : 8)
                .fixedSize(horizontal: false, vertical: true)

            if !inputFocused, let review = p.review {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(review, id: \.self) { r in
                        Text(r.question).font(.caption).foregroundStyle(.secondary)
                        Text("→ \(r.answer.isEmpty ? "（沒答）" : r.answer)").font(.callout)
                    }
                }
            }

            if !inputFocused {
                let list = VStack(spacing: 6) {
                    ForEach(options, id: \.key) { o in
                        OptionButton(
                            option: o,
                            description: current.description(for: o.label),
                            selected: o.key == p.selected,
                            disabled: sending
                        ) { act { try await $0.key(sessionID, o.key) } }
                    }
                }
                // 量出清單的實際高度：放得下就照原本高度，超過 300 才在框內捲動（不留空白）
                ScrollView {
                    list.background(GeometryReader { g in
                        Color.clear.preference(key: OptionsHeightKey.self, value: g.size.height)
                    })
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(optionsHeight, 1), 300))
                .onPreferenceChange(OptionsHeightKey.self) { optionsHeight = $0 }

                if let submit = p.submit_key {
                    let n = p.options.filter { $0.checked == true }.count
                    Button { act { try await $0.key(sessionID, submit) } } label: {
                        Text(n == 0 ? "送出（沒有勾任何一項）" : "送出選擇（已勾 \(n) 項）")
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                    .tint(.orange)
                    .disabled(sending)
                }
            }
        }
    }

    private var keyRow: some View {
        HStack(spacing: 6) {
            ForEach([("↑", "up"), ("↓", "down"), ("Tab", "tab"), ("⏎", "enter"), ("Esc", "esc")], id: \.1) { label, key in
                Button { act { try await $0.key(sessionID, key) } } label: {
                    Text(label).font(.callout.weight(.medium)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    /// 搜尋結果點下去：那一則還沒載入就一頁一頁往前載（最多 20 頁），載到了再捲過去
    private func jump(to id: String) async {
        guard let api = store.api else { return }
        var pages = 0
        while !messages.contains(where: { $0.id == id }), hasMore, pages < 20, let first = messages.first?.id {
            guard let d = try? await api.session(sessionID, before: first, limit: Self.pageSize) else { break }
            let have = Set(messages.map(\.id))
            messages = d.messages.filter { !have.contains($0.id) } + messages
            hasMore = d.has_more ?? false
            pages += 1
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        scrollTarget = id
    }

    /// 一次抓幾則。模擬器驗收可用 SR_PAGE 調小，才看得到「載入更早的訊息」
    private static var pageSize: Int {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["SR_PAGE"].flatMap(Int.init) { return v }
        #endif
        return 150
    }

    private func loadOlder(_ proxy: ScrollViewProxy) async {
        guard let api = store.api, let first = messages.first?.id else { return }
        loadingOlder = true
        defer { loadingOlder = false }
        do {
            let anchor = ChatItem.group(messages).first?.id
            let d = try await api.session(sessionID, before: first, limit: Self.pageSize)
            let have = Set(messages.map(\.id))
            messages = d.messages.filter { !have.contains($0.id) } + messages
            hasMore = d.has_more ?? false
            // 停在原本看的那一則，不要跳到最上面
            if let anchor { proxy.scrollTo(anchor, anchor: .top) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// 照片縮到長邊 2048、存成 JPEG 傳到筆電，把路徑放進輸入框（自己補一句話再送）
    private func sendPhoto(_ item: PhotosPickerItem) async {
        guard let api = store.api else { return }
        uploading = true
        defer { uploading = false; photoItem = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self), let img = UIImage(data: raw) else {
                error = "讀不到這張照片"
                return
            }
            let jpeg = Self.shrink(img).jpegData(compressionQuality: 0.8) ?? raw
            let path = try await api.upload(sessionID, jpeg: jpeg)
            text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + "（圖片：\(path)）"
            inputFocused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func shrink(_ img: UIImage, maxSide: CGFloat = 2048) -> UIImage {
        let side = max(img.size.width, img.size.height)
        guard side > maxSide else { return img }
        let scale = maxSide / side
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }

    private func act(_ f: @escaping (API) async throws -> Void) {
        guard let api = store.api else { return }
        sending = true
        Task {
            do {
                try await f(api)
                error = nil
                try? await Task.sleep(nanoseconds: 600_000_000)
                await load()
            } catch {
                self.error = error.localizedDescription
            }
            sending = false
        }
    }

    private func load() async {
        guard let api = store.api else { return }
        do {
            let d = try await api.session(sessionID, after: messages.last?.id, limit: Self.pageSize, screen: showScreen)
            if d.reset ?? true {
                messages = d.messages
                hasMore = d.has_more ?? false
            } else {
                // 兩次更新重疊時可能拿到同一段，用 id 去重
                let have = Set(messages.map(\.id))
                messages += d.messages.filter { !have.contains($0.id) }
            }
            detail = d
            error = nil
            #if DEBUG
            // 模擬器驗收：SR_TOOL=<訊息 id>，或 SR_TOOL=Bash 開最後一個那種工具
            if openTool == nil, let t = ProcessInfo.processInfo.environment["SR_TOOL"] {
                openTool = messages.last { $0.id == t || ($0.role == "tool" && $0.tool == t) }
            }
            #endif
        } catch is CancellationError {
            // 換頁或新的一次更新取消了這次，不是錯誤
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// 一個選項按鈕：標籤＋說明（說明從 hook 回報的題目來，畫面上只看得到標籤）。
private struct OptionButton: View {
    let option: PromptOption
    let description: String?
    let selected: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        let (label, recommended) = Self.split(option.label)
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                if let checked = option.checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(checked ? Color.orange : Color.secondary)
                        .frame(width: 22, height: 22)
                } else {
                    Text(option.key.hasPrefix("pick:") ? String(option.key.dropFirst(5)) : option.key)
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .frame(width: 22, height: 22)
                        .background(selected ? Color.orange : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(selected ? .white : .secondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(label).font(.callout.weight(.medium)).foregroundStyle(.primary)
                        if recommended {
                            Text("推薦").font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    if let description, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected && option.checked == nil ? Color.orange.opacity(0.7) : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    static func split(_ label: String) -> (String, Bool) {
        for tag in [" (Recommended)", "(Recommended)", "（Recommended）"] where label.hasSuffix(tag) {
            return (String(label.dropLast(tag.count)).trimmingCharacters(in: .whitespaces), true)
        }
        return (label, false)
    }
}

/// 一次問好幾題時，hook 回報的是整張題目表，畫面上顯示的卻是「目前這一題」的選項。
/// 用選項標籤比對出目前是第幾題，題目與說明才不會錯配（之前一律拿第一題）。
struct PromptMatch {
    let question: Question?
    let index: Int
    let total: Int

    init(pending: Pending?, prompt: Prompt) {
        let qs = pending?.kind == "ask" ? (pending?.questions ?? []) : []
        total = qs.count
        let screen = prompt.options.map { Self.norm($0.label) }
        var best = (index: 0, score: -1)
        for (i, q) in qs.enumerated() {
            let score = (q.options ?? []).filter { o in
                let n = Self.norm(o.label)
                return screen.contains { Self.same($0, n) }
            }.count
            if score > best.score { best = (i, score) }
        }
        index = best.index
        question = qs.isEmpty ? nil : qs[best.index]
    }

    var title: String? { question?.question }

    var badge: String? {
        guard let q = question else { return nil }
        let head = q.header ?? "選一個"
        return total > 1 ? "\(head) · 第 \(index + 1)／\(total) 題" : head
    }

    func description(for label: String) -> String? {
        let n = Self.norm(label)
        return question?.options?.first { Self.same(Self.norm($0.label), n) }?.description
    }

    private static func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// 終端機太窄時標籤會被截斷，所以前綴相同也算
    private static func same(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a == b || (min(a.count, b.count) >= 6 && (a.hasPrefix(b) || b.hasPrefix(a)))
    }
}

/// session 名稱慣例是「專案｜第一句摘要」
struct SessionName {
    let project: String
    let summary: String?

    init(_ name: String) {
        if let r = name.range(of: "｜") {
            project = String(name[..<r.lowerBound])
            let s = String(name[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            summary = s.isEmpty ? nil : s
        } else {
            project = name
            summary = nil
        }
    }
}

private struct OptionsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension ChatItem {
    func contains(_ messageID: String) -> Bool {
        switch self {
        case .message(let m): return m.id == messageID
        case .tools(let ms): return ms.contains { $0.id == messageID }
        }
    }
}

/// 對話內搜尋：問筆電（整段紀錄都找得到，不只手機已經載入的那段）
struct ConversationSearch: View {
    let sessionID: String
    let onPick: (String) -> Void
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var searched = false
    #if DEBUG
    init(sessionID: String, onPick: @escaping (String) -> Void) {
        self.sessionID = sessionID
        self.onPick = onPick
        _query = State(initialValue: ProcessInfo.processInfo.environment["SR_SEARCH"] ?? "")
    }
    #endif

    var body: some View {
        NavigationStack {
            List {
                ForEach(hits) { h in
                    Button { onPick(h.id) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.role == "user" ? "你" : h.role == "tool" ? (h.tool ?? "工具") : "Claude")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(h.role == "user" ? Color.accentColor : .secondary)
                            Text(highlight(h.snippet)).font(.callout).lineLimit(3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .overlay {
                if searched && hits.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "找對話裡的字")
            .task(id: query) {
                // 打字停 0.3 秒再問，不要每個字都打一次 API
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled, let api = store.api else { return }
                let q = query.trimmingCharacters(in: .whitespaces)
                if q.isEmpty { hits = []; searched = false; return }
                hits = (try? await api.search(sessionID, query: q)) ?? []
                searched = true
            }
            .navigationTitle("搜尋對話")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }

    private func highlight(_ s: String) -> AttributedString {
        var a = AttributedString(s)
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let r = a.range(of: q, options: .caseInsensitive) {
            a[r].backgroundColor = .yellow.opacity(0.4)
            a[r].font = .callout.weight(.semibold)
        }
        return a
    }
}
