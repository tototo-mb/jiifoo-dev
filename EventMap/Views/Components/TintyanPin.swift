import SwiftUI
import RiveRuntime

// イベントピンのキャラクター「ちんちゃん」(tintyan.riv)
// ・数値(TintyanValues)を入れると、その大きさ・動き・色で描く
// ・状況ごとの数値(開催前・タップしたとき・開催中)もここにまとめる

// tintyan.riv に入れる数値(Rive の ViewModel の値)
struct TintyanValues: Equatable {
    var bodyTate: Float = 150      // bodytate:体の縦の長さ
    var bodyYoko: Float = 40       // bodyyoko:体の横の太さ
    var sandTate: Float = 10       // sandtate:砂の縦
    var sandYoko: Float = 60       // sandyoko:砂の横
    var swayWidth: Float = 5       // swayswidth:揺れの幅
    var swaySpeed: Float = 1       // swaysspead:揺れの速さ
    var waveStrength: Float = 3    // wavestrength:うねりの強さ
    var waveWidth: Float = 10      // wavewidth:うねりの幅
    var waveSpeed: Float = 1       // wavespead:うねりの速さ
    var outlineWidth: Float = 0    // hutidori:縁取りの太さ

    // 色(Rive の色の値)
    var bodyColor: SwiftUI.Color = .black          // bodycolor:体の色
    var bodySideColor: SwiftUI.Color = .black      // bodysidecolor:体のふちの色
    var outlineColor: SwiftUI.Color = .black       // huticolor:縁取りの色
    var sandColor: SwiftUI.Color = .black          // sandcolor:砂の色
    var holeColor: SwiftUI.Color = .black          // holecolor:穴の色

    // まとめて書き写す用の文字
    var summary: String {
        String(format: "体 縦%.0f 横%.0f / 砂 縦%.0f 横%.0f / 揺れ 幅%.1f 速さ%.1f / うねり 強さ%.1f 幅%.1f 速さ%.1f / 縁取り %.1f",
               bodyTate, bodyYoko, sandTate, sandYoko, swayWidth, swaySpeed, waveStrength, waveWidth, waveSpeed, outlineWidth)
        + "\n色 体\(bodyColor.hexText) ふち\(bodySideColor.hexText) 縁取り\(outlineColor.hexText) 砂\(sandColor.hexText) 穴\(holeColor.hexText)"
    }

    // 2つの数値の間(t = 0 なら自分、1 なら相手)。なめらかに変えるときに使う
    // ・速さ(揺れ・うねり)は途中の値にすると動きがガタつくので、はじめから相手の値にする
    // ・色も相手の色にする
    func mixed(with other: TintyanValues, t: Float) -> TintyanValues {
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        var result = other
        result.bodyTate = mix(bodyTate, other.bodyTate)
        result.bodyYoko = mix(bodyYoko, other.bodyYoko)
        result.sandTate = mix(sandTate, other.sandTate)
        result.sandYoko = mix(sandYoko, other.sandYoko)
        result.swayWidth = mix(swayWidth, other.swayWidth)
        result.waveStrength = mix(waveStrength, other.waveStrength)
        result.waveWidth = mix(waveWidth, other.waveWidth)
        result.outlineWidth = mix(outlineWidth, other.outlineWidth)
        return result
    }
}

// MARK: - 状況ごとの数値

extension TintyanValues {
    // 開催前(ふだん)
    static let beforeStart = TintyanValues(bodyTate: 39, bodyYoko: 72, sandTate: 10, sandYoko: 99,
                                           swayWidth: 5, swaySpeed: 1,
                                           waveStrength: 0, waveWidth: 10, waveSpeed: 1)
    // 開催前のピンをタップしたとき(キャラが出てくる)
    static let selected = TintyanValues(bodyTate: 155, bodyYoko: 40, sandTate: 10, sandYoko: 60,
                                        swayWidth: 17.5, swaySpeed: 2.5,
                                        waveStrength: 0, waveWidth: 10, waveSpeed: 1)
    // 開催中(写真が0枚のとき)
    static let liveBase = TintyanValues(bodyTate: 185, bodyYoko: 33, sandTate: 22, sandYoko: 70,
                                        swayWidth: 10, swaySpeed: 1,
                                        waveStrength: 0, waveWidth: 15, waveSpeed: 2)

    // 開催中:撮られた写真の枚数に合わせて盛り上げる
    // ・1枚ごとに、5つの値のうち1つをランダムに選んで上げる(上限に届いた値は選ばない)
    // ・ランダムはイベントIDから決めるので、誰が見ても・何度読み込んでも同じ形になる
    static func live(photoCount: Int, eventID: UUID) -> TintyanValues {
        var values = liveBase
        var random = SeededRandom(seed: eventID)
        for _ in 0..<max(photoCount, 0) {
            // まだ上限に届いていない値だけを候補にする
            let candidates = Growth.allCases.filter { !$0.isMax(in: values) }
            guard !candidates.isEmpty else { break }   // 全部上限なら、もう上げない
            let picked = candidates[random.next(below: candidates.count)]
            picked.grow(&values)
        }
        return values
    }

    // 写真で上げる値と、1枚で上げる量・上限
    private enum Growth: CaseIterable {
        case bodyTate, swayWidth, swaySpeed, waveSpeed, waveWidth

        // 上げる量と上限
        var step: Float {
            switch self {
            case .bodyTate:  return 50
            case .swayWidth: return 5
            case .swaySpeed: return 2
            case .waveSpeed: return 2
            case .waveWidth: return 5
            }
        }
        var maxValue: Float {
            switch self {
            case .bodyTate:  return 385
            case .swayWidth: return 60    // テスト画面のスライダーの上限
            case .swaySpeed: return 10
            case .waveSpeed: return 10
            case .waveWidth: return 60
            }
        }

        // その値を取り出す・書きかえる場所
        private var keyPath: WritableKeyPath<TintyanValues, Float> {
            switch self {
            case .bodyTate:  return \.bodyTate
            case .swayWidth: return \.swayWidth
            case .swaySpeed: return \.swaySpeed
            case .waveSpeed: return \.waveSpeed
            case .waveWidth: return \.waveWidth
            }
        }

        func isMax(in values: TintyanValues) -> Bool {
            values[keyPath: keyPath] >= maxValue
        }

        func grow(_ values: inout TintyanValues) {
            values[keyPath: keyPath] = min(values[keyPath: keyPath] + step, maxValue)
        }
    }
}

// 決まった種(イベントID)から、いつも同じ順番で数を出すランダム
// (Swift の .random は毎回変わるので、ここでは使わない)
private struct SeededRandom {
    private var state: UInt64

    init(seed: UUID) {
        // UUID の16バイトのうち、前の8バイトを種にする
        let b = seed.uuid
        state = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7]
            .reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    // 0 から count - 1 までの数を1つ出す(SplitMix64 という計算)
    mutating func next(below count: Int) -> Int {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Int(z % UInt64(count))
    }
}

// MARK: - 表示

// tintyan.riv を、数値を入れて表示する
// animated: true なら、数値が変わったときに少し行き過ぎてから戻る動き(0.6秒)で、なめらかに変える
struct TintyanView: View {
    let values: TintyanValues
    var animated = false

    // 枠の下のあき(キャラの足元は、枠の上から78%のところにある。下の22%は空き)
    static let emptyBottomRatio: CGFloat = 0.22
    // なめらかに変える時間(秒)
    private static let duration: Double = 1.2

    @StateObject private var riveVM = RiveViewModel(
        fileName: "tintyan",
        stateMachineName: "State Machine 1"
    )
    @State private var shown: TintyanValues?          // 今 Rive に入っている数値
    @State private var change: Change?                // 変えている途中のとき(どこから・どこへ・いつから)

    private struct Change {
        let from: TintyanValues
        let to: TintyanValues
        let start: Date
    }

    var body: some View {
        // 変えている途中だけ、画面の書きかえ(1秒に60回など)に合わせて数値を進める
        TimelineView(.animation(paused: change == nil)) { context in
            riveVM.view()
                .onChange(of: context.date) { _, now in
                    step(at: now)
                }
        }
        .onAppear {
            // ファイルの中の ViewModel につないで、つながったら数値を入れる
            riveVM.riveModel?.enableAutoBind { _ in
                apply(shown ?? values)
            }
            apply(values)
        }
        .onChange(of: values) { oldValue, newValue in
            if animated {
                change = Change(from: shown ?? oldValue, to: newValue, start: .now)
            } else {
                apply(newValue)
            }
        }
    }

    // 変えている途中:今の時刻から、どこまで進んだかを計算して数値を入れる
    private func step(at now: Date) {
        guard let change else { return }
        let t = min(now.timeIntervalSince(change.start) / Self.duration, 1)
        apply(change.from.mixed(with: change.to, t: Float(Self.easeOutBack(t))))
        if t >= 1 {
            self.change = nil   // 終わったら、画面の書きかえに合わせるのをやめる
        }
    }

    // はじめ速く、少し行き過ぎてから戻る動き(t: 0〜1)
    private static func easeOutBack(_ t: Double) -> Double {
        let c1 = 1.2                // 行き過ぎる強さ(大きいほど行き過ぎる)
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    // Rive の ViewModel に数値を入れる(名前は Rive エディタで付けた名前と同じにする)
    private func apply(_ values: TintyanValues) {
        shown = values
        guard let instance = riveVM.riveModel?.stateMachine?.viewModelInstance else { return }
        instance.numberProperty(fromPath: "bodytate")?.value = values.bodyTate
        instance.numberProperty(fromPath: "bodyyoko")?.value = values.bodyYoko
        instance.numberProperty(fromPath: "sandtate")?.value = values.sandTate
        instance.numberProperty(fromPath: "sandyoko")?.value = values.sandYoko
        instance.numberProperty(fromPath: "swayswidth")?.value = values.swayWidth
        instance.numberProperty(fromPath: "swaysspead")?.value = values.swaySpeed
        instance.numberProperty(fromPath: "wavestrength")?.value = values.waveStrength
        instance.numberProperty(fromPath: "wavewidth")?.value = values.waveWidth
        instance.numberProperty(fromPath: "wavespead")?.value = values.waveSpeed
        instance.numberProperty(fromPath: "hutidori")?.value = values.outlineWidth
        instance.colorProperty(fromPath: "bodycolor")?.value = UIColor(values.bodyColor)
        instance.colorProperty(fromPath: "bodysidecolor")?.value = UIColor(values.bodySideColor)
        instance.colorProperty(fromPath: "huticolor")?.value = UIColor(values.outlineColor)
        instance.colorProperty(fromPath: "sandcolor")?.value = UIColor(values.sandColor)
        instance.colorProperty(fromPath: "holecolor")?.value = UIColor(values.holeColor)
    }
}

extension SwiftUI.Color {
    // 「#FF8800」の形の文字(色を書き写す用)
    var hexText: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}