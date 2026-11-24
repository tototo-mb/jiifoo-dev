import SwiftUI

// 会場に到着したときに、参加スタンプを「ドン」と押す演出
// ・紙(カード)が出る → 大きく傾いたスタンプが上から落ちて押される → 少し待って消える
// ・画面をタップすると、すぐに消せる
struct ArrivalStampOverlay: View {
    let stamp: ParticipationStamp
    var onFinished: () -> Void       // 演出が終わったら呼ぶ(呼んだ側で消す)

    @State private var isStamped = false   // スタンプが押されたか
    @State private var isFading = false    // 消えている途中か

    var body: some View {
        ZStack {
            // 後ろを少し暗くする
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            // 紙の上にスタンプを押す
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .frame(width: 320, height: 280)
                ParticipationStampView(stamp: stamp)
                    .frame(width: 280)
                    // 押す前：大きく・傾いて・見えない → 押した後：元の大きさ
                    .scaleEffect(isStamped ? 1 : 2.5)
                    .rotationEffect(.degrees(isStamped ? 0 : -20))
                    .opacity(isStamped ? 1 : 0)
            }
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        }
        .opacity(isFading ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        // 押した瞬間に「ドン」と振動
        .sensoryFeedback(.impact(weight: .heavy), trigger: isStamped)
        .task {
            // 紙が出てから少し待って押す
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                isStamped = true
            }
            // 見せる時間
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.4)) {
                isFading = true
            }
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            onFinished()
        }
    }
}

// 到着したイベントからスタンプの内容を作る
extension ParticipationStamp {
    // 途中参加型(マップで自動的に到着したとき)
    init(event: Event) {
        self.init(eventID: event.id,
                  title: event.title,
                  organizerName: nil,
                  date: event.startsAt,
                  isCorporate: event.kind == "corporate")
    }

    // 時間厳守型(集合モードで「到着しました」を押したとき)
    init(event: GatheringEvent, organizerName: String?) {
        self.init(eventID: event.id,
                  title: event.title,
                  organizerName: organizerName,
                  date: event.startsAt,
                  isCorporate: event.kind == "corporate")
    }
}

#Preview {
    Color.blue.opacity(0.3)
        .ignoresSafeArea()
        .overlay {
            ArrivalStampOverlay(stamp: ParticipationStamp(
                eventID: UUID(), title: "缶蹴り", organizerName: "ユーザー名",
                date: .now, isCorporate: false)) { }
        }
}