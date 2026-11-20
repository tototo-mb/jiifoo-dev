import ActivityKit
import WidgetKit
import SwiftUI

// 集合までのカウントダウン（ダイナミックアイランド・ロック画面）
struct GatheringWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GatheringAttributes.self) { context in
            // ---- ロック画面・通知の上に出る表示 ----
            HStack(spacing: 12) {
                Image(systemName: icon(context))
                    .font(.title2)               
                    .foregroundStyle(.purple)         
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(label(context))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // 集合モードが始まる時刻(集合の5分前)
                    if !isOver(context) && !context.attributes.isDropIn {
                        HStack(spacing: 0) {
                            Text(modeStart(context), style: .time)
                            Text("から集合モード")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                }

                Spacer()

                countdown(context)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .frame(width: 110, alignment: .trailing)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.65))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                // ---- 長押しで大きく開いたとき ----
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.isDropIn ? "開始" : "集合", systemImage: icon(context))
                        .font(.headline)
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .frame(width: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.eventTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: icon(context))
                    .foregroundStyle(.purple)
            } compactTrailing: {
                countdown(context)
                    .font(.caption.bold())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: icon(context))
                    .foregroundStyle(.purple)
            }
        }
    }

    // 集合モードが始まる時刻(集合の5分前。サーバーの event_phase と同じ)
    private func modeStart(_ context: ActivityViewContext<GatheringAttributes>) -> Date {
        context.state.meetTime.addingTimeInterval(-5 * 60)
    }

        // アイコン(途中参加OK型はお祭りっぽく)
    private func icon(_ context: ActivityViewContext<GatheringAttributes>) -> String {
        context.attributes.isDropIn ? "party.popper" : "figure.walk.motion"
    }

    // カウントダウンの上の文字
    private func label(_ context: ActivityViewContext<GatheringAttributes>) -> String {
        if context.attributes.isDropIn {
            return isOver(context) ? "開始しました" : "開始まで"
        }
        return isOver(context) ? "集合時刻です" : "集合まで"
    }



    // 集合時刻を過ぎたか
    private func isOver(_ context: ActivityViewContext<GatheringAttributes>) -> Bool {
        context.isStale || context.state.meetTime <= .now
    }

    // 残り時間。0になったら「集合！」
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<GatheringAttributes>) -> some View {
        if isOver(context) {
            Text(context.attributes.isDropIn ? "開始！" : "集合！")
                .foregroundStyle(.orange)
        } else {
            Text(timerInterval: Date.now...context.state.meetTime, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
