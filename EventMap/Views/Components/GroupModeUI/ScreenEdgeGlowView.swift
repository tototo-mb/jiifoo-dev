import SwiftUI
import CoreHaptics

// リズムの1打
struct RhythmHit {
    enum Kind { case don, tsu }   // ドン：重く大きい / ツ：軽く固い
    let time: Double              // リズムが始まってから何秒後に鳴らすか
    let kind: Kind

    static func don(_ time: Double) -> RhythmHit { RhythmHit(time: time, kind: .don) }
    static func tsu(_ time: Double) -> RhythmHit { RhythmHit(time: time, kind: .tsu) }
}

// 集合モード中に、画面のふちを Siri 風に光らせる（華やか＆上品版 ＋ リズム振動）
// ・2枚の光が逆向きに回って重なる
// ・白い光の筋がふちを流れる
// ・リズムに合わせて、ふちが広がり、ドンのたびに波紋が内側へ広がる
struct ScreenEdgeGlowView: View {
    var cornerRadius: CGFloat = 55

    // ---- 太さ・ぼかし ----
    var lineWidth: CGFloat = 3.5        // くっきりした線の太さ
    var glowWidth: CGFloat = 18         // ぼけた光の太さ
    var glowBlur: CGFloat = 12          // ぼかしの強さ
    var haloOpacity: Double = 0.35      // 外側のふんわりした光の濃さ
    var shimmerOpacity: Double = 0.7    // 流れる光の筋の濃さ
    var saturation: Double = 1.3        // 色の鮮やかさ（1が元の色）
    var maxOpacity: Double = 0.95       // 一番明るいときの濃さ

    // ---- 動き ----
    var secondsPerTurn: Double = 4      // 1周にかける秒数（大きいほどゆっくり）
    var pulseSeconds: Double = 1.0      // 明るさが脈打つ速さ
    var pulseMinOpacity: Double = 0.6   // 脈打つときの一番暗い明るさ（1に近いほど控えめ）
    var startScale: CGFloat = 2.6       // つく瞬間に何倍まで広がるか
    var donScale: CGFloat = 1.5         // 「ドン」で何倍まで広がるか
    var tsuScale: CGFloat = 1.1         // 「ツ」で何倍まで広がるか
    var rippleDistance: CGFloat = 45    // 波紋が内側へ広がる距離(pt)

    // ---- リズム（ここを書き換えるとリズムが変わる）----
    // 「ドン、ツツ、ドン、ツ」
    var rhythm: [RhythmHit] = [
        .don(0.00),   // ドン
        .tsu(0.80),   // ツ
        .tsu(0.90),   // ツ
        .tsu(1.40)    // ツ
    ]
    var rhythmInterval: Double = 1.2    // リズムとリズムの間の休み(秒)

    // ---- 振動 ----
    var rhythmHaptics = true            // リズムに合わせて振動させるか

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0
    @State private var isVisible = false
    @State private var scale: CGFloat = 1
    @State private var isPulsing = false
    @State private var flash: Double = 0              // ドンの瞬間の明るさ（白飛びしない範囲）
    @State private var rippleProgress: CGFloat = 1    // 波紋の進み具合（0: ふち → 1: 消えた）
    @State private var haptics: GlowHaptics?

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

    // 流れる光の筋（ほとんど透明で、一か所だけ白く光る）
    private static let shimmerStops: [Gradient.Stop] = [
        .init(color: .clear, location: 0.00),
        .init(color: .clear, location: 0.40),
        .init(color: .white.opacity(0.9), location: 0.48),
        .init(color: .clear, location: 0.56),
        .init(color: .clear, location: 1.00)
    ]

    var body: some View {
        GeometryReader { geo in
            // 回しても四隅が欠けないよう、画面より大きい正方形にする
            let side = max(geo.size.width, geo.size.height) * 1.5

            ZStack {
                // ① 色の光：2枚を逆向きに回して重ねる
                ZStack {
                    AngularGradient(colors: Self.colors, center: .center)
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(rotation))

                    AngularGradient(colors: Self.colors.reversed(), center: .center)
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(-rotation))   // 必ず整数倍（つなぎ目でカクッとしない）
                        .blendMode(.plusLighter)
                        .opacity(0.45)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .mask { edgeMask }
                .opacity(isPulsing ? maxOpacity : maxOpacity * pulseMinOpacity)

                // ② 流れる光の筋：細い線の上だけを、2倍の速さで走る
                AngularGradient(stops: Self.shimmerStops, center: .center)
                    .frame(width: side, height: side)
                    .rotationEffect(.degrees(rotation * 2))
                    .frame(width: geo.size.width, height: geo.size.height)
                    .mask { shimmerMask }
                    .blendMode(.plusLighter)
                    .opacity(shimmerOpacity)
            }
            .saturation(saturation)
            .brightness(flash)
            .drawingGroup()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(isVisible ? 1 : 0)
        .task { await run() }
    }

    // 色の光の形（オーラ ＋ ぼけた光 ＋ 線 ＋ 波紋）
    private var edgeMask: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            // 外側のふんわりしたオーラ
            shape.stroke(lineWidth: glowWidth * 3).blur(radius: glowBlur * 2.5)
                .opacity(haloOpacity)
            // ぼけた光
            shape.stroke(lineWidth: glowWidth * scale).blur(radius: glowBlur * scale)
            // くっきりした線
            shape.stroke(lineWidth: lineWidth * min(scale, 1.8))
            // 波紋（角の丸みを保ったまま、太く柔らかくにじみながら内側へ消える）
            RoundedRectangle(cornerRadius: max(cornerRadius - rippleDistance * rippleProgress * 0.3, 24),
                             style: .continuous)
                .stroke(lineWidth: 4 + 14 * rippleProgress)
                .blur(radius: 3 + 12 * rippleProgress)
                .padding(rippleDistance * rippleProgress)
                .opacity(0.8 * (1 - rippleProgress))
        }
    }

    // 光の筋が走る細い線
    private var shimmerMask: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(lineWidth: lineWidth * 1.4)
            .blur(radius: 1)
    }

    // MARK: - 演出の流れ

    @MainActor
    private func run() async {
        if haptics == nil { haptics = GlowHaptics() }

        // 「視差効果を減らす」がオンなら、ふわっと出すだけ
        guard !reduceMotion else {
            withAnimation(.easeIn(duration: 0.4)) { isVisible = true }
            isPulsing = true
            haptics?.launch()
            return
        }

        // ① 登場：広がりながら出現 ＋ 波紋 ＋ 重い開幕振動
        haptics?.launch()
        flash = 0.15
        withAnimation(.easeOut(duration: 0.25)) {
            isVisible = true
            scale = startScale
        }
        withAnimation(.easeOut(duration: 0.6)) { flash = 0 }
        startRipple(duration: 1.2)
        try? await Task.sleep(for: .seconds(0.25))
        guard !Task.isCancelled else { return }

        // ② ばねのように普段のサイズへ戻る
        withAnimation(.spring(duration: 1.1, bounce: 0.35)) { scale = 1 }

        // ③ 回る ＋ 脈打つ
        withAnimation(.linear(duration: secondsPerTurn).repeatForever(autoreverses: false)) {
            rotation = 360
        }
        withAnimation(.easeInOut(duration: pulseSeconds).repeatForever(autoreverses: true)) {
            isPulsing = true
        }

        // ④ 一定間隔でリズムを繰り返す
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rhythmInterval))
            guard !Task.isCancelled else { return }
            // 振動はリズム全体をまとめて1回で鳴らす（タイミングがずれない）
            if rhythmHaptics { haptics?.play(rhythm: rhythm) }
            await playRhythmVisual()
        }
    }

    // リズムに合わせた光の動き（振動と同じタイミング）
    @MainActor
    private func playRhythmVisual() async {
        let start = ContinuousClock.now
        for hit in rhythm {
            // リズム開始から hit.time 秒後まで待つ（ずれが積み重ならない）
            try? await Task.sleep(until: start + .seconds(hit.time), clock: .continuous)
            guard !Task.isCancelled else { return }

            switch hit.kind {
            case .don:
                // ドン：大きく広がる ＋ 波紋 ＋ 一瞬明るく
                startRipple(duration: 1.0)
                flash = 0.1
                withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
                bump(to: donScale)
            case .tsu:
                // ツ：少しだけピクッ
                bump(to: tsuScale)
            }
        }
        try? await Task.sleep(for: .seconds(0.4))   // 最後の余韻
    }

    // ふちを一瞬ふくらませて、ばねで戻す
    @MainActor
    private func bump(to target: CGFloat) {
        withAnimation(.easeOut(duration: 0.06)) { scale = target }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.spring(duration: 0.4, bounce: 0.3)) { scale = 1 }
        }
    }

    // 波紋：ふちに戻してから、内側へ広がりながら消す
    @MainActor
    private func startRipple(duration: Double) {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { rippleProgress = 0 }   // 一瞬でふちに戻す
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(16))   // 1コマ待ってから動かす
            withAnimation(.easeOut(duration: duration)) {
                rippleProgress = 1
            }
        }
    }
}

// MARK: - 振動（Core Haptics）
// ドン：「コツッ」という一撃 ＋ 「ズン…」という低い響き
// ツ　：軽くて固い「ツッ」
final class GlowHaptics {
    private var engine: CHHapticEngine?

    // ---- 振動の強さ・重さ（ここを変えると手ざわりが変わる）----
    var donIntensity: Float = 1.0       // ドンの強さ（0〜1）
    var donRumble: TimeInterval = 0.2   // ドンの響きの長さ(秒)。長いほど重い
    var tsuIntensity: Float = 0.55      // ツの強さ（0〜1）
    var tsuSharpness: Float = 0.9       // ツの硬さ（1に近いほどカチッ）

    init() {
        // 振動に対応していない端末（シミュレーターなど）では何もしない
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        // 着信などで止まったら、次に鳴らすときに自動で立ち上げ直す
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
    }

    // 光り始め：ドドドッ ＋ ゴゴゴ…（長めの重い揺れ）
    func launch() {
        var events: [CHHapticEvent] = []
        events += thump(at: 0.00, intensity: 1.0, rumble: 0.10)
        events += thump(at: 0.09, intensity: 1.0, rumble: 0.10)
        events += thump(at: 0.18, intensity: 1.0, rumble: 0.10)
        events.append(rumble(at: 0.28, intensity: 1.0, duration: 0.35))
        play(events)
    }

    // リズム全体の振動
    func play(rhythm: [RhythmHit]) {
        var events: [CHHapticEvent] = []
        for hit in rhythm {
            switch hit.kind {
            case .don:
                events += thump(at: hit.time, intensity: donIntensity, rumble: donRumble)
            case .tsu:
                events.append(tap(at: hit.time, intensity: tsuIntensity))
            }
        }
        play(events)
    }

    // 軽くて固い一撃（響きなし）＝「ツ」
    private func tap(at time: TimeInterval, intensity: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: tsuSharpness)
                      ],
                      relativeTime: time)
    }

    // 鋭い一撃 ＋ 低い響き ＝「ドン」
    private func thump(at time: TimeInterval, intensity: Float, rumble duration: TimeInterval) -> [CHHapticEvent] {
        [
            CHHapticEvent(eventType: .hapticTransient,
                          parameters: [
                            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                          ],
                          relativeTime: time),
            rumble(at: time, intensity: intensity, duration: duration)
        ]
    }

    // 低くて重い響き（sharpness が小さいほど「ズン」と重くなる）
    private func rumble(at time: TimeInterval, intensity: Float, duration: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous,
                      parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.05)
                      ],
                      relativeTime: time,
                      duration: duration)
    }

    private func play(_ events: [CHHapticEvent]) {
        guard let engine else { return }
        do {
            try engine.start()
            let pattern = try CHHapticPattern(events: events, parameters: [])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
        } catch {
            // 振動できなくても光は動くので、何もしない
        }
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
