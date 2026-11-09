import SwiftUI

// 集合モード中に、画面のふちを Siri 風に光らせる
// ・つく瞬間：ドンッと大きく広がる ＋ 振動
// ・ついている間：色が回る ＋ 明るさが脈打つ ＋ 数秒ごとに「ドクン・ドクン」と広がる
struct ScreenEdgeGlowView: View {
    var cornerRadius: CGFloat = 55

    // ---- 太さ・ぼかし ----
    var lineWidth: CGFloat = 6          // くっきりした線の太さ
    var glowWidth: CGFloat = 26         // ぼけた光の太さ
    var glowBlur: CGFloat = 12          // ぼかしの強さ（大きいほど重くなる）
    var saturation: Double = 1.4        // 色の鮮やかさ（1が元の色）

    // ---- 動き ----
    var secondsPerTurn: Double = 3      // 1周にかける秒数（小さいほど速く回る）
    var pulseSeconds: Double = 0.6      // 明るさが脈打つ速さ（小さいほど速い）
    var pulseMinOpacity: Double = 0.15   // 脈打つときの一番暗い明るさ（0〜1）
    var startScale: CGFloat = 4         // つく瞬間に何倍まで広がるか
    var beatScale: CGFloat = 3       // 「ドクン」で何倍まで広がるか
    var beatInterval: Double = 1.5      // 「ドクン・ドクン」の間隔(秒)
    var beatHaptics = false             // 「ドクン」のたびに振動させるか

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var isVisible = false
    @State private var scale: CGFloat = 1     // 今の広がり具合（1が普段）
    @State private var isPulsing = false      // 脈打ち（明るい側）か
    @State private var hapticCount = 0        // 増えるたびに1回振動する

    // Siri っぽい色（最後に最初の色を足して、つなぎ目を目立たなくする）
    private static let colors: [Color] = [
        Color(red: 0.74, green: 0.51, blue: 0.95),  // 紫
        Color(red: 0.96, green: 0.73, blue: 0.92),  // 薄いピンク
        Color(red: 0.55, green: 0.62, blue: 1.00),  // 青
        Color(red: 0.30, green: 0.80, blue: 1.00),  // 水色
        Color(red: 1.00, green: 0.40, blue: 0.47),  // 赤
        Color(red: 1.00, green: 0.73, blue: 0.44),  // オレンジ
        Color(red: 0.40, green: 0.70, blue: 1.00),  // 青
        Color(red: 0.78, green: 0.53, blue: 1.00),  // 紫
        Color(red: 0.74, green: 0.51, blue: 0.95)   // 最初の紫（つなぎ目用）
    ]

    var body: some View {
        GeometryReader { geo in
            // 回しても四隅が欠けないよう、画面より大きい正方形にする
            let side = max(geo.size.width, geo.size.height) * 1.5

            AngularGradient(colors: Self.colors, center: .center)
                .frame(width: side, height: side)
                .rotationEffect(.degrees(rotation))          // 回転だけで色を動かす（軽い）
                .frame(width: geo.size.width, height: geo.size.height)
                .mask { edgeMask }                            // ふちの形だけ見せる
                .saturation(saturation)
                .opacity(isPulsing ? 1 : pulseMinOpacity)     // 明るさが脈打つ（軽い）
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)          // 下の地図の操作を邪魔しない
        .opacity(isVisible ? 1 : 0)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: hapticCount)
        .task { await run() }
    }

    // ふちの形（くっきりした線 ＋ ぼけた光）。scale が大きいほど太く・強くぼかす
    private var edgeMask: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape.stroke(lineWidth: glowWidth * scale).blur(radius: glowBlur * scale)
            shape.stroke(lineWidth: lineWidth * min(scale, 2))
        }
    }

    // 演出の流れ
    @MainActor
    private func run() async {
        // 「視差効果を減らす」がオンなら、ふわっと出すだけ
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.4)) { isVisible = true }
            isPulsing = true
            return
        }

        // ① ドンッと大きく広がりながら出てくる ＋ 振動
        hapticCount += 1
        withAnimation(.easeOut(duration: 0.18)) {
            isVisible = true
            scale = startScale
        }
        try? await Task.sleep(for: .seconds(0.18))
        guard !Task.isCancelled else { return }

        // ② ばねのように普段の太さへ戻る
        withAnimation(.spring(duration: 1.0, bounce: 0.5)) { scale = 1 }

        // ③ ずっと回る ＋ 明るさが脈打つ
        withAnimation(.linear(duration: secondsPerTurn).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: pulseSeconds).repeatForever(autoreverses: true)) {
            isPulsing = true
        }

        // ④ 数秒ごとに「ドクン・ドクン」
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(beatInterval))
            guard !Task.isCancelled else { return }
            await beat(to: beatScale)          // ドクン（大きめ）
            await beat(to: beatScale * 0.75)   // ドクン（小さめ）
        }
    }

    // 1回の「ドクン」：さっと広がって、ばねで戻る
    @MainActor
    private func beat(to target: CGFloat) async {
        if beatHaptics { hapticCount += 1 }
        withAnimation(.easeOut(duration: 0.1)) { scale = target }
        try? await Task.sleep(for: .seconds(0.1))
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) { scale = 1 }
        try? await Task.sleep(for: .seconds(0.2))
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ScreenEdgeGlowView()
    }
}

// MARK: - どの画面にも付けられるようにする

extension View {
    /// 画面のふちを Siri 風に光らせる
    /// - Parameter isActive: true のあいだ光る（false にするとふわっと消える）
    func screenEdgeGlow(_ isActive: Bool, cornerRadius: CGFloat = 55) -> some View {
        overlay {
            if isActive {
                ScreenEdgeGlowView(cornerRadius: cornerRadius)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isActive)
    }
}
