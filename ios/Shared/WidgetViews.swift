import SwiftUI
import WidgetKit

// 小工具與鎖定畫面的畫面本體。放在 Shared 是為了讓 app 的除錯預覽頁也能畫（模擬器沒辦法擺小工具、鎖螢幕）。

struct WaitingEntry: TimelineEntry {
    let date: Date
    let sessions: [SessionSummary]
    let error: String?

    /// 標了星號的排前面
    var waiting: [SessionSummary] {
        sessions.filter { $0.status == "waiting" }.sorted { ($0.starred == true ? 0 : 1) < ($1.starred == true ? 0 : 1) }
    }
    var working: [SessionSummary] { sessions.filter { $0.status == "working" } }
    var background: [SessionSummary] { sessions.filter { $0.status == "background" } }
}

struct WaitingWidgetView: View {
    let entry: WaitingEntry
    /// app 裡的預覽頁用（小工具本身由系統告訴它是哪種大小）
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var systemFamily
    private var family: WidgetFamily { familyOverride ?? systemFamily }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.waiting.count)").font(.title2.weight(.bold))
                    Image(systemName: "questionmark.bubble").font(.caption2)
                }
            }
            .widgetURL(URL(string: "sessionremote://open"))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("等你 \(entry.waiting.count)・工作中 \(entry.working.count)").font(.headline)
                if let w = entry.waiting.first {
                    Text("\(w.project)：\(w.pending?.headline ?? "")").font(.caption).lineLimit(2)
                } else if let err = entry.error {
                    Text(err).font(.caption)
                }
            }
            .widgetURL(URL(string: "sessionremote://open" + (entry.waiting.first.map { "?id=\($0.id)" } ?? "")))
        case .systemSmall:
            small
        default:
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                Text("等你回答").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Text("\(entry.waiting.count)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(entry.waiting.isEmpty ? Color.secondary : Color.orange)
            Spacer(minLength: 0)
            if let err = entry.error {
                Text(err).font(.caption2).foregroundStyle(.red)
            } else {
                Label("工作中 \(entry.working.count)", systemImage: "ellipsis.circle")
                    .font(.caption2).foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sessionremote://open" + (entry.waiting.first.map { "?id=\($0.id)" } ?? "")))
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("等你 \(entry.waiting.count)", systemImage: "questionmark.bubble.fill").foregroundStyle(.orange)
                Label("工作中 \(entry.working.count)", systemImage: "ellipsis.circle").foregroundStyle(.blue)
                if !entry.background.isEmpty {
                    Label("背景 \(entry.background.count)", systemImage: "hourglass").foregroundStyle(.purple)
                }
                Spacer()
                Text(entry.date, style: .time).foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.semibold))
            if let err = entry.error {
                Spacer()
                Text(err).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else if entry.waiting.isEmpty {
                Spacer()
                Text(entry.working.isEmpty && entry.background.isEmpty ? "沒有要你處理的" : "都在跑，沒有在等你")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(entry.waiting.prefix(3)) { s in
                    Link(destination: URL(string: "sessionremote://open?id=\(s.id)")!) {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 3) {
                                if s.starred == true {
                                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                                }
                                Text(s.project).font(.caption.weight(.semibold)).lineLimit(1).foregroundStyle(.primary)
                            }
                            Text(s.pending?.headline ?? String(localized: "等你回答")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    .tint(.primary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct LockScreenView: View {
    let state: SessionsActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                count(state.waiting, String(localized: "等你"), "questionmark.bubble.fill", .orange)
                count(state.working, String(localized: "工作中"), "ellipsis.circle.fill", .blue)
                if state.background > 0 {
                    count(state.background, String(localized: "背景"), "hourglass.circle.fill", .purple)
                }
                count(state.done, String(localized: "完工"), "checkmark.circle.fill", .green)
                Spacer()
            }
            Text(state.headline)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
        }
    }

    private func count(_ n: Int, _ label: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text("\(n)").font(.headline.monospacedDigit()).foregroundStyle(.white)
            // 英文的標籤比較長（Background），寧可縮小也不要斷成兩行
            Text(label).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}
