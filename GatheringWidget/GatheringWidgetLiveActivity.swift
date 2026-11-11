import ActivityKit
import WidgetKit
import SwiftUI

// 集合までのカウントダウン（ダイナミックアイランド・ロック画面）
struct GatheringWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GatheringAttributes.self) { context in
            // ---- ロック画面・通知の上に出る表示 ----
            HStack(spacing: 12) {
                Image(systemName: "figure.walk.motion")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.eventTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(isOver(context) ? "集合時刻です" : "集合まで")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Label("集合", systemImage: "figure.walk.motion")
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
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(.purple)
            } compactTrailing: {
                countdown(context)
                    .font(.caption.bold())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "figure.walk.motion")
                    .foregroundStyle(.purple)
            }
        }
    }

    // 集合時刻を過ぎたか
    private func isOver(_ context: ActivityViewContext<GatheringAttributes>) -> Bool {
        context.isStale || context.state.meetTime <= .now
    }

    // 残り時間。0になったら「集合！」
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<GatheringAttributes>) -> some View {
        if isOver(context) {
            Text("集合！")
                .foregroundStyle(.orange)
        } else {
            Text(timerInterval: Date.now...context.state.meetTime, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}
