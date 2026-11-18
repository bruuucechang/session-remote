import Foundation

/// 列表與對話頁共用題目辨識、選項過濾及翻譯；送出的 label 一律保留原文。
struct PromptPresentation {
    let prompt: Prompt
    let options: [PromptOption]
    let match: PromptMatch
    let words: PromptWords

    init(detail: SessionDetail, prompt: Prompt) {
        self.prompt = prompt
        options = prompt.options.filter { option in
            let typing = option.key == prompt.type_key && (option.label.hasPrefix("Type something")
                || ["Other", "其他"].contains(option.label.trimmingCharacters(in: CharacterSet(charactersIn: ".")))) // l10n:skip 比對原文
            return !typing && !option.label.hasPrefix("Chat about")
        }
        match = PromptMatch(pending: detail.pending, prompt: prompt)
        words = PromptWords(pending: detail.pending, prompt: prompt, match: match, cwd: detail.cwd,
                            awaitingTool: detail.awaiting_tool?.tool)
    }

    static func split(_ label: String) -> (String, Bool) {
        for tag in [" (Recommended)", "(Recommended)", "（Recommended）"] where label.hasSuffix(tag) {  // l10n:skip 比對 Claude Code 原文
            return (String(label.dropLast(tag.count)).trimmingCharacters(in: .whitespaces), true)
        }
        return (label, false)
    }

    /// 列表只處理按一下就送的選項；要接著打字、信任資料夾、複選與確認頁進對話處理。
    var quickOptions: [PromptOption] {
        guard prompt.submit_key == nil, prompt.review == nil,
              [.ask, .permission, .plan].contains(words.kind) else { return [] }
        return options.filter { $0.key != prompt.type_key }
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
        let head = q.header ?? String(localized: "選一個")
        return total > 1 ? String(localized: "\(head) · 第 \(index + 1)／\(total) 題") : head
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

/// 題目卡的標頭、標題與選項顯示的字。選項題用 hook 回報的題目；權限提示、計畫核准、信任資料夾、
/// 確認頁是 Claude Code 自己的選單，標籤固定是英文，認得的就翻成中文（認不得的照原文）。
struct PromptWords {
    enum Kind { case review, trust, plan, ask, permission, other }

    let kind: Kind
    let badge: String
    let title: String
    /// 權限提示：要用的工具（從通知「Claude needs your permission to use Bash」取出）
    let tool: String?

    /// awaitingTool：後端認出來正在等權限的那一則工具呼叫（拿不準就是 nil）。新版的通知只寫
    /// 「Claude needs your permission」、沒寫是哪個工具（2026-10-26 v2.1.310 實測），這時用它
    init(pending: Pending?, prompt: Prompt, match: PromptMatch, cwd: String, awaitingTool: String? = nil) {
        let message = pending?.message ?? ""
        let tool = message.range(of: #"permission to use (\S+)"#, options: .regularExpression)
            .map { String(message[$0].split(separator: " ").last ?? "") } ?? awaitingTool
        if let review = prompt.review {
            kind = .review
            badge = String(localized: "確認答案 · 共 \(review.count) 題")
            title = String(localized: "要送出這幾題的答案嗎？")
        } else if pending?.kind != "ask",
                  prompt.options.contains(where: { ["Yes, I trust this folder", "Yes, proceed"].contains($0.label) }),
                  prompt.options.contains(where: { $0.label == "No, exit" }) {
            // 剛開、還沒回報過的 session 卡在這裡：hook 還沒跑，只有畫面上的選項
            kind = .trust
            badge = String(localized: "第一次在這個資料夾開 Claude")
            let name = (cwd as NSString).lastPathComponent
            title = name.isEmpty ? String(localized: "要信任這個資料夾嗎？") : String(localized: "要信任「\(name)」這個資料夾嗎？")
        } else if pending?.plan == true
                    // 權限通知可能把 hook 記的 plan 旗子蓋掉：畫面上是計畫核准的選項也算
                    || prompt.options.contains(where: { $0.label == "Tell Claude what to change" || $0.label.hasPrefix("Yes, and use auto mode") }) {
            kind = .plan
            badge = String(localized: "計畫核准")
            title = message.isEmpty ? String(localized: "計畫寫好了，要照著做嗎？") : serverText(message)
        } else if pending?.kind == "ask" {
            kind = .ask
            badge = match.badge ?? String(localized: "選一個")
            title = match.title ?? pending?.headline ?? String(localized: "Claude 在等你選")
        } else if pending?.kind == "permission" {
            kind = .permission
            badge = String(localized: "要你允許")
            title = tool.map { String(localized: "Claude 要用 \($0)，允許嗎？") }
                ?? (message.isEmpty || message.hasPrefix("Claude needs your permission") ? String(localized: "Claude 要你允許，允許嗎？") : message)
        } else {
            kind = .other
            badge = String(localized: "Claude 在等你")
            title = pending?.headline ?? String(localized: "Claude 在等你選")
        }
        self.tool = kind == .permission ? tool : nil
    }

    func label(_ raw: String) -> String {
        // 權限提示最後一項帶著「(esc)」：手機上沒有 Esc 鍵的意思
        let s = raw.hasSuffix(" (esc)") ? String(raw.dropLast(6)) : raw
        switch kind {
        case .review:
            return ["Submit answers": String(localized: "送出答案"), "Cancel": String(localized: "取消，回去改")][s] ?? s
        case .trust:
            return ["No, exit": String(localized: "不信任，離開"), "Yes, I trust this folder": String(localized: "信任這個資料夾"),
                    "Yes, proceed": String(localized: "信任，繼續")][s] ?? s
        case .plan:
            if let t = ["Yes, and use auto mode": String(localized: "核准，接著自動做"), "Yes, manually approve edits": String(localized: "核准，每次改檔先問我"),
                        "Yes, and auto-accept edits": String(localized: "核准，改檔不用問我"), "Tell Claude what to change": String(localized: "要改計畫（按了再打字）")][s] {
                return t
            }
            return s
        case .permission:
            if s == "Yes" { return String(localized: "允許") }
            if s == "No" { return String(localized: "不允許") }
            if s.hasPrefix("No, and tell Claude") { return String(localized: "不允許，告訴 Claude 怎麼做（按了再打字）") }
            if s.hasPrefix("Yes, and don't ask again") {
                // 後半段是規則（「for npm run build commands in …」），照原文留著
                let rest = s.dropFirst("Yes, and don't ask again".count).trimmingCharacters(in: .whitespaces)
                return rest.isEmpty ? String(localized: "允許，之後不再問") : String(localized: "允許，之後不再問：\(rest)")
            }
            if s.hasPrefix("Yes, allow all edits") { return String(localized: "允許，這次 session 改檔都不再問") }
            return s
        case .ask, .other:
            return s
        }
    }
}

