import SwiftUI

/// 對話串的一列：一則訊息，或連續的工具呼叫折成一組。
enum ChatItem: Identifiable {
    case message(Message)
    case tools([Message])

    var id: String {
        switch self {
        case .message(let m): return m.id
        case .tools(let ms): return "tools-" + (ms.first?.id ?? "")
        }
    }

    static func group(_ messages: [Message]) -> [ChatItem] {
        var out: [ChatItem] = []
        var run: [Message] = []
        for m in messages {
            if m.role == "tool" { run.append(m); continue }
            if !run.isEmpty { out.append(.tools(run)); run = [] }
            out.append(.message(m))
        }
        if !run.isEmpty { out.append(.tools(run)) }
        return out
    }
}

struct MessageView: View {
    let m: Message
    @State private var expanded = false

    var body: some View {
        switch m.role {
        case "user":
            HStack {
                Spacer(minLength: 48)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(m.text)
                        .lineLimit(expanded ? nil : 12)
                        .textSelection(.enabled)
                    if isLong {
                        Button(expanded ? "收起" : "展開全文") { expanded.toggle() }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case "system":
            Text(m.text)
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(Color(.tertiarySystemFill), in: Capsule())
                .frame(maxWidth: .infinity)
        default:
            MarkdownView(source: m.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isLong: Bool { m.text.count > 500 || m.text.filter { $0 == "\n" }.count > 11 }
}

/// 連續的工具呼叫：一個就一行；多個預設折起來，只看最後一個在做什麼。
struct ToolGroupView: View {
    let tools: [Message]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if tools.count == 1 || expanded {
                ForEach(tools) { row($0) }
            } else if let last = tools.last {
                row(last)
            }
            if tools.count > 1 {
                Button {
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    Label(expanded ? "收起" : "共 \(tools.count) 個工具呼叫", systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ m: Message) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon(m.tool ?? ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(m.tool ?? "").font(.caption.weight(.semibold))
            Text(m.text).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func icon(_ tool: String) -> String {
        switch tool {
        case "Bash": return "terminal"
        case "Read": return "doc.text"
        case "Edit", "Write", "NotebookEdit": return "pencil"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebFetch", "WebSearch": return "globe"
        case "Agent", "Task": return "person.2"
        case "AskUserQuestion": return "questionmark.bubble"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Markdown

/// Claude 回覆的區塊級 Markdown：段落、標題、清單、引言、程式碼區塊、表格。
/// SwiftUI 的 AttributedString 只認行內語法，清單與 ``` 會原樣印出來，所以區塊自己切。
struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MDBlock.parse(source).enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ b: MDBlock) -> some View {
        switch b {
        case .paragraph(let s):
            Text(inline(s))
        case .heading(let level, let s):
            Text(inline(s))
                .font(level <= 1 ? .title3.weight(.bold) : level == 2 ? .headline : .subheadline.weight(.semibold))
                .padding(.top, 4)
        case .bullet(let indent, let marker, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary).monospacedDigit()
                Text(inline(s))
            }
            .padding(.leading, CGFloat(indent) * 14)
        case .quote(let s):
            Text(inline(s))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Capsule().fill(Color(.systemGray3)).frame(width: 3) }
        case .code(let s), .table(let s):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(s)
                    .font(.system(.footnote, design: .monospaced))
                    .fixedSize()
                    .padding(10)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .rule:
            Divider()
        }
    }

    private func inline(_ s: String) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
        for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
            a[run.range].font = .system(size: 15, design: .monospaced)
            a[run.range].foregroundColor = Color(.systemPink)
        }
        return a
    }
}

enum MDBlock {
    case paragraph(String)
    case heading(Int, String)
    case bullet(Int, String, String)
    case quote(String)
    case code(String)
    case table(String)
    case rule

    static func parse(_ text: String) -> [MDBlock] {
        var out: [MDBlock] = []
        var para: [String] = []
        var code: [String]? = nil
        var table: [String] = []

        func flushPara() { if !para.isEmpty { out.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
        func flushTable() { if !table.isEmpty { out.append(.table(table.joined(separator: "\n"))); table = [] } }

        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if code != nil {
                if line.hasPrefix("```") { out.append(.code(code!.joined(separator: "\n"))); code = nil }
                else { code!.append(raw) }
                continue
            }
            if line.hasPrefix("```") { flushPara(); flushTable(); code = []; continue }
            if line.hasPrefix("|") { flushPara(); table.append(line); continue }
            flushTable()
            if line.isEmpty { flushPara(); continue }
            if line == "---" || line == "***" { flushPara(); out.append(.rule); continue }
            if let h = heading(line) { flushPara(); out.append(h); continue }
            if line.hasPrefix(">") {
                flushPara()
                out.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if let b = bullet(raw) { flushPara(); out.append(b); continue }
            para.append(line)
        }
        if let c = code { out.append(.code(c.joined(separator: "\n"))) }
        flushPara(); flushTable()
        return out
    }

    private static func heading(_ line: String) -> MDBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func bullet(_ raw: String) -> MDBlock? {
        let indent = raw.prefix { $0 == " " }.count / 2
        let line = raw.trimmingCharacters(in: .whitespaces)
        for p in ["- ", "* ", "+ "] where line.hasPrefix(p) {
            return .bullet(indent, "•", String(line.dropFirst(2)))
        }
        // 1. 2) 這種編號
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return .bullet(indent, digits + ".", String(rest.dropFirst(2)))
            }
        }
        return nil
    }
}
