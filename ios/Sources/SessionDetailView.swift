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

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let d = detail, d.total_messages > d.messages.count {
                            Text("（前面還有 \(d.total_messages - d.messages.count) 則）")
                                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                        ForEach(detail?.messages ?? []) { m in
                            MessageView(m: m).id(m.id)
                        }
                        if showScreen, let screen = detail?.screen, !screen.isEmpty {
                            Text(screen.joined(separator: "\n"))
                                .font(.system(size: 10, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(.white)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }
                .onChange(of: detail?.messages.last?.id) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            Divider()
            controls
        }
        .navigationTitle(detail?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(detail?.name ?? "").font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let d = detail {
                        Text("\(Status.label(d.status)) · \(d.account.label ?? "")")
                            .font(.caption2).foregroundStyle(Status.color(d.status))
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
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task(id: store.tick) { await load() }
        .task { await load() }
    }

    @ViewBuilder private var controls: some View {
        VStack(spacing: 8) {
            if let err = error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let d = detail {
                if let p = d.prompt {
                    promptView(d, p)
                } else if d.status == "working" {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(d.activity.isEmpty ? "工作中…" : d.activity)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(role: .destructive) { act { try await $0.interrupt(sessionID) } } label: {
                            Label("中斷", systemImage: "stop.circle.fill")
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
            if showKeys { keyRow }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(detail?.prompt?.type_key != nil ? "或自己打一個答案…" : "回覆…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                Button {
                    let t = text
                    act { try await $0.reply(sessionID, text: t); text = "" }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                .accessibilityLabel("送出")
            }
        }
        .padding(10)
        .background(.bar)
    }

    @ViewBuilder private func promptView(_ d: SessionDetail, _ p: Prompt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(d.pending?.headline ?? "Claude 在等你選")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(p.options.filter { $0.key != p.type_key && !$0.label.hasPrefix("Chat about") }, id: \.key) { o in
                        Button { act { try await $0.key(sessionID, o.key) } } label: {
                            HStack {
                                Text(o.label).multilineTextAlignment(.leading)
                                Spacer()
                                if let desc = description(for: o, in: d) {
                                    Text(desc).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .tint(o.key == p.selected ? .orange : .accentColor)
                        .disabled(sending)
                    }
                }
            }
            .frame(maxHeight: 260)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 選項題的說明文字從 hook 回報的題目裡拿（畫面上只看得到標籤）
    private func description(for o: PromptOption, in d: SessionDetail) -> String? {
        guard let opts = d.pending?.questions?.first?.options else { return nil }
        return opts.first { $0.label == o.label }?.description
    }

    private var keyRow: some View {
        HStack {
            ForEach([("↑", "up"), ("↓", "down"), ("Tab", "tab"), ("⏎", "enter"), ("Esc", "esc")], id: \.1) { label, key in
                Button(label) { act { try await $0.key(sessionID, key) } }
                    .buttonStyle(.bordered).controlSize(.small)
                    .frame(maxWidth: .infinity)
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
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct MessageView: View {
    let m: Message

    var body: some View {
        switch m.role {
        case "user":
            HStack {
                Spacer(minLength: 40)
                Text(m.text)
                    .padding(10)
                    .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        case "system":
            Text(m.text)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case "tool":
            Label {
                Text("\(m.tool ?? "")  \(m.text)").lineLimit(1)
            } icon: {
                Image(systemName: "wrench.and.screwdriver")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        default:
            Text(markdown(m.text))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
