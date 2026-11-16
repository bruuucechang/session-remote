import SwiftUI

/// 點工具那一行打開的頁面：完整的指令／路徑、改了什麼（紅綠差異）、它的輸出。
struct ToolDetailView: View {
    let sessionID: String
    let message: Message
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ToolDetail?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let d = detail {
                        content(d)
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding()
            }
            .navigationTitle(message.tool ?? String(localized: "工具"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
            .task { await load() }
        }
    }

    @ViewBuilder private func content(_ d: ToolDetail) -> some View {
        let input = d.input.mapValues(\.text)
        switch d.tool {
        case "Bash":
            if let desc = input["description"] { Text(desc).font(.subheadline.weight(.semibold)) }
            section(String(localized: "指令")) { code(input["command"] ?? "") }
        case "Edit":
            path(input["file_path"])
            section(String(localized: "改動")) { DiffView(old: input["old_string"] ?? "", new: input["new_string"] ?? "") }
        case "Write":
            path(input["file_path"])
            section(String(localized: "寫入的內容")) { DiffView(old: "", new: input["content"] ?? "") }
        case "Read":
            path(input["file_path"])
        default:
            section(String(localized: "輸入")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(input.keys.sorted(), id: \.self) { k in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(input[k] ?? "").font(.callout).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        if let out = d.output {
            section(d.is_error ? String(localized: "錯誤") : String(localized: "輸出")) {
                code(out.isEmpty ? String(localized: "（沒有輸出）") : out + (d.output_truncated ? String(localized: "\n…（太長，後面截掉了）") : ""),
                     tint: d.is_error ? .red : nil)
            }
        } else {
            Text("還沒有輸出（可能還在跑）").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func path(_ p: String?) -> some View {
        Label(p ?? "", systemImage: "doc.text")
            .font(.footnote.monospaced())
            .textSelection(.enabled)
    }

    private func section<V: View>(_ title: String, @ViewBuilder _ body: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            body()
        }
    }

    private func code(_ s: String, tint: Color? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(s)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(tint ?? .primary)
                .textSelection(.enabled)
                .fixedSize()
                .padding(10)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func load() async {
        guard let api = store.api else { return }
        do { detail = try await api.toolDetail(sessionID, message: message.id) }
        catch { self.error = error.localizedDescription }
    }
}

/// 行為單位的差異：刪掉的紅底「-」、加上的綠底「+」、沒變的灰字。
struct DiffView: View {
    let old: String
    let new: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.diff(old, new).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Text(line.mark).foregroundStyle(line.color)
                        Text(line.text.isEmpty ? " " : line.text)
                    }
                    .font(.system(.footnote, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.color.opacity(line.mark == " " ? 0 : 0.14))
                }
            }
            .fixedSize()
            .padding(.vertical, 6)
            .textSelection(.enabled)
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    struct Line { let mark: String; let text: String; let color: Color }

    /// 最長共同子序列（LCS）逐行比對；太長就不比、整段當刪掉＋加上，免得卡住手機
    static func diff(_ a: String, _ b: String) -> [Line] {
        let x = a.isEmpty ? [] : a.components(separatedBy: "\n")
        let y = b.isEmpty ? [] : b.components(separatedBy: "\n")
        let minus = { (s: String) in Line(mark: "-", text: s, color: .red) }
        let plus = { (s: String) in Line(mark: "+", text: s, color: .green) }
        guard x.count * y.count <= 250_000 else { return x.map(minus) + y.map(plus) }
        var t = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in stride(from: x.count - 1, through: 0, by: -1) {
            for j in stride(from: y.count - 1, through: 0, by: -1) {
                t[i][j] = x[i] == y[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var out: [Line] = []
        var i = 0, j = 0
        while i < x.count || j < y.count {
            if i < x.count, j < y.count, x[i] == y[j] {
                out.append(Line(mark: " ", text: x[i], color: .secondary)); i += 1; j += 1
            } else if i < x.count, j == y.count || t[i + 1][j] >= t[i][j + 1] {
                // 刪掉的排在加上的前面（跟 git diff 一樣）
                out.append(minus(x[i])); i += 1
            } else {
                out.append(plus(y[j])); j += 1
            }
        }
        return out
    }
}
