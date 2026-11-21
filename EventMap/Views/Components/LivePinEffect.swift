import SwiftUI

// 開催中(開始時刻を過ぎた)イベントのピンに付ける目印
// ・足元に広がる波紋
// ・ピンの上に「LIVE」
// 「視差効果を減らす」がオンのときは、波紋を動かさない
struct LivePinEffect: ViewModifier {
    let isLive: Bool

    func body(content: Content) -> some View {
        content
            // 足元の波紋(ピンの後ろに出す)
            .background(alignment: .bottom) {
                if isLive {
                    LiveRipple()
                        .offset(y: 6)
                }
            }
            // 上の「LIVE」
            .overlay(alignment: .top) {
                if isLive {
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .offset(y: -10)
                }
            }
    }
}

// 足元に広がって消えていく輪(2つを少しずらして繰り返す)
struct LiveRipple: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { index in
                Ellipse()
                    .stroke(.orange, lineWidth: 2)
                    .frame(width: 44, height: 16)
                    .scaleEffect(isAnimating ? 2.2 : 0.6)
                    .opacity(isAnimating ? 0 : 0.9)
                    .animation(
                        reduceMotion ? nil :
                            .easeOut(duration: 1.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.8),
                        value: isAnimating
                    )
            }
        }
        .allowsHitTesting(false)   // 波紋はタップに反応させない
        .onAppear {
            if !reduceMotion { isAnimating = true }
        }
    }
}

extension View {
    /// 開催中なら、足元の波紋と「LIVE」の印を付ける
    func livePinEffect(_ isLive: Bool) -> some View {
        modifier(LivePinEffect(isLive: isLive))
    }
}

#Preview {
    VStack(spacing: 40) {
        BusinessPinView(isJoinable: true).livePinEffect(true)
        PrivatePinView(isJoinable: true).livePinEffect(true)
    }
}