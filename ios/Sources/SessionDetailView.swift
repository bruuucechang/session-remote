import SwiftUI

struct SessionDetailView: View {
    let sessionID: String
    @EnvironmentObject var store: Store
    @State private var detail: SessionDetail?
    @State private var error: String?
    @State private var text = ""
    @State private var sending = false
    @State private var showKeys = false
    @State private var showScreen = false
    @FocusState private var inputFocused: Bool
    @State private var optionsHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let d = detail, d.total_messages > d.messages.count {
                        Text("前面還有 \(d.total_messages - d.messages.count) 則")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    if detail == nil && error == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(ChatItem.group(detail?.messages ?? [])) { item in
                        switch item {
                        case .message(let m): MessageView(m: m)
                        case .tools(let ms): ToolGroupView(tools: ms)
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
            .onChange(of: detail?.messages.last?.id) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
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
                    Text(detail.map { SessionName($0.name).project } ?? "")
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let d = detail {
                        HStack(spacing: 4) {
                            Circle().fill(Status.color(d.status)).frame(width: 6, height: 6)
                            Text("\(Status.label(d.status)) · \(d.account.label ?? "")")
                        }
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showScreen.toggle() } label: {
                        Label(showScreen ? "隱藏終端機畫面" : "顯示終端機畫面", systemImage: "terminal")
                    }
                    Button { showKeys.toggle() } label: {
                        Label(showKeys ? "隱藏按鍵列" : "顯示按鍵列", systemImage: "keyboard")
                    }
                } label: { Image(systemName: "ellipsis") }
            }
        }
        // .task(id:) 進畫面時也會跑一次，不用另外掛 .task
        .task(id: store.tick) { await load() }
        #if DEBUG
        // 模擬器驗收：SR_DRAFT 預先填好輸入框（\n 換行）、SR_FOCUS=1 叫出鍵盤，看長文字會不會跑出框外
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if let d = env["SR_DRAFT"], text.isEmpty { text = d.replacingOccurrences(of: "\\n", with: "\n") }
            if env["SR_FOCUS"] == "1" { inputFocused = true }
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
                Text(current.badge ?? "Claude 在等你")
                Spacer()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)

            Text(current.title ?? d.pending?.headline ?? "Claude 在等你選")
                .font(.subheadline.weight(.semibold))
                // 打字的時候只留兩行，把位置讓給輸入框
                .lineLimit(inputFocused ? 2 : 8)
                .fixedSize(horizontal: false, vertical: true)

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
            detail = try await api.session(sessionID)
            error = nil
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
