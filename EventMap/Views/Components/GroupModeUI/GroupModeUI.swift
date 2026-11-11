import SwiftUI
import ActivityKit

// =====================================================
// 集合モードの UI まとめ
//
// 【集合機能の担当の人へ】使い方はこれだけです
//
//   @Environment(GatheringMode.self) private var gathering
//
//   gathering.start(title: "イベント名", meetTime: 集合時刻)   // 始める
//   gathering.stop()                                           // やめる
//
// start すると自動で：
//   ・画面のふちが光る（ScreenEdgeGlowView.swift）
//   ・地図の上に「集合まで 09:41」が出る
//   ・ダイナミックアイランド／ロック画面にカウントダウンが出る
//   ・集合時刻になったら全部消える
// =====================================================


// MARK: - 集合モードの状態（アプリ全体で1つだけ持つ）

@Observable @MainActor
final class GatheringMode {
    private(set) var meetTime: Date?      // 集合時刻（集合モード中だけ入る）
    private(set) var title = ""           // イベント名

    var isActive: Bool { meetTime != nil }

    /// 集合モードを始める
    func start(title: String, meetTime: Date) {
        self.title = title
        withAnimation(.spring) { self.meetTime = meetTime }
        Task { await GatheringActivityManager.start(title: title, meetTime: meetTime) }
    }

    /// 「◯分後に集合」で始める（テスト用にも便利）
    func start(title: String, minutes: Double) {
        start(title: title, meetTime: .now.addingTimeInterval(minutes * 60))
    }

    /// 集合モードを終える（光・カウントダウン・ダイナミックアイランドが全部消える）
    func stop() {
        withAnimation(.spring) { meetTime = nil }
        Task { await GatheringActivityManager.end() }
    }

    /// 集合時刻を過ぎていたら終える
    func stopIfExpired() {
        if let meetTime, meetTime <= .now { stop() }
    }
}


// MARK: - 画面に付ける演出（光 ＋ 上部のカウントダウン ＋ 0で終了）

private struct GatheringModeOverlay: ViewModifier {
    @Environment(GatheringMode.self) private var gathering
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // 画面のふちの光
            .screenEdgeGlow(gathering.isActive)
            // 上部中央のカウントダウン
            .overlay(alignment: .top) {
                if let meetTime = gathering.meetTime {
                    GatheringCountdownView(meetTime: meetTime)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            // 集合時刻になったら終える
            .task(id: gathering.meetTime) {
                guard let meetTime = gathering.meetTime else { return }
                let wait = meetTime.timeIntervalSinceNow
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
                gathering.stop()
            }
            // アプリに戻ってきたとき、もう過ぎていたら終える
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { gathering.stopIfExpired() }
            }
    }
}

extension View {
    /// 集合モード中の演出（光・カウントダウン）を付ける
    func gatheringModeOverlay() -> some View {
        modifier(GatheringModeOverlay())
    }
}


// MARK: - 地図の上に出す「集合まで 09:41」

struct GatheringCountdownView: View {
    let meetTime: Date

    var body: some View {
        // 1秒ごとに描き直す
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, Int(meetTime.timeIntervalSince(context.date).rounded(.up)))
            let isHurry = remaining <= 60   // 残り1分を切ったら急ぎ表示

            HStack(spacing: 10) {
                Image(systemName: "figure.walk.motion")
                    .font(.title3)
                    .foregroundStyle(isHurry ? .red : .purple)
                    .symbolEffect(.pulse, isActive: isHurry)

                VStack(alignment: .leading, spacing: 0) {
                    Text("集合まで")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(Self.format(remaining))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isHurry ? .red : .primary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: remaining)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
    }

    // 秒数を「09:41」の形にする
    private static func format(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}


// MARK: - ダイナミックアイランド／ロック画面のカウントダウンを出す・消す

@MainActor
enum GatheringActivityManager {

    /// カウントダウンを始める（前のものがあれば消してから）
    static func start(title: String, meetTime: Date) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("🟣 LiveActivity: Info.plist か iPhone の設定でオフになっています")
            return
        }
        await end()

        let content = ActivityContent(
            state: GatheringAttributes.ContentState(meetTime: meetTime),
            staleDate: meetTime   // 集合時刻を過ぎたら、表示が「集合！」に切り替わる
        )
        do {
            _ = try Activity.request(
                attributes: GatheringAttributes(eventTitle: title),
                content: content,
                pushType: nil
            )
        } catch {
            print("🟣 LiveActivity: 開始できませんでした \(error)")
        }
    }

    /// カウントダウンを消す
    static func end() async {
        for activity in Activity<GatheringAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}


// MARK: - プレビュー

#Preview("カウントダウン") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        GatheringCountdownView(meetTime: .now.addingTimeInterval(75))
    }
}
