import ActivityKit
import SwiftUI
import WidgetKit

@main
struct SessionWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WaitingWidget()
        SessionsLiveActivity()
    }
}

// MARK: - 主畫面／鎖定畫面小工具：等你回答的清單

struct WaitingProvider: TimelineProvider {
    func placeholder(in _: Context) -> WaitingEntry { WaitingEntry(date: .now, sessions: [], error: nil) }

    func getSnapshot(in _: Context, completion: @escaping (WaitingEntry) -> Void) {
        Task { completion(await load()) }
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<WaitingEntry>) -> Void) {
        // 系統給小工具的更新額度有限：15 分鐘自己抓一次，app 開著時每次更新會叫它重抓
        Task {
            let e = await load()
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    private func load() async -> WaitingEntry {
        guard let api = SharedConfig.api else {
            return WaitingEntry(date: .now, sessions: [], error: String(localized: "先打開 app 連到筆電"))
        }
        do {
            return WaitingEntry(date: .now, sessions: try await api.sessions().sessions, error: nil)
        } catch {
            return WaitingEntry(date: .now, sessions: [], error: String(localized: "連不上筆電"))
        }
    }
}

struct WaitingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WaitingWidget", provider: WaitingProvider()) { e in
            WaitingWidgetView(entry: e)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("等你回答")
        .description("哪幾個 session 在等你、幾個在工作。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 鎖定畫面與動態島的即時狀態

struct SessionsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionsActivityAttributes.self) { ctx in
            LockScreenView(state: ctx.state)
                .padding(14)
                .activityBackgroundTint(Color.black.opacity(0.6))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(URL(string: "sessionremote://open"))
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("等你 \(s.waiting)", systemImage: "questionmark.bubble.fill")
                        .foregroundStyle(.orange).font(.headline).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(s.headline).font(.callout).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "questionmark.bubble.fill").foregroundStyle(.orange)
                    .frame(minWidth: 28, alignment: .leading)
            } compactTrailing: {
                Text("\(s.waiting)").foregroundStyle(.orange).monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            } minimal: {
                HStack(spacing: 2) {
                    Image(systemName: "questionmark.bubble.fill")
                    Text("\(s.waiting)")
                }
                .font(.caption2).foregroundStyle(.orange).monospacedDigit()
            }
            .widgetURL(URL(string: "sessionremote://open"))
        }
    }
}

