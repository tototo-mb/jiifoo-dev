import SwiftUI
import RiveRuntime

// 新しいピン(pin3.riv)と、ピンの種類の切り替え
// ※ 2026-11-27 に pin2.riv から pin3.riv に変更(型の名前は Pin2〜 のまま)
// ・ふだんは新しいピン。設定画面の「ピンの種類」で、旧ピン(ちんちゃん)に切り替えられる
// ・タップしたときは、pin3.riv の回転の合図(spinTrigger)を送り、少し大きくする
// ・開催中は、足元の波紋(LivePinEffect)で目立たせる

// MARK: - ピンの種類

enum PinStyle: String, CaseIterable, Identifiable {
    case pin2      // 新しいピン(今は pin3.riv。保存済みの設定が変わらないよう、名前は pin2 のまま)
    case tintyan   // 旧ピン(ちんちゃん、tintyan.riv)

    // 設定に保存するときの名前(@AppStorage で使う)
    static let storageKey = "pinStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pin2:    return "kkawon"
        case .tintyan: return "あなごくん"
        }
    }
}

// MARK: - pin3.riv の読み込み(アプリ全体で1回だけ)

// ※ 起動時に裏のスレッドで読み込むので、メインスレッド専用(MainActor)にしない
nonisolated enum Pin2Rive {
    nonisolated(unsafe) static let file: RiveFile? = try? RiveFile(name: "pin3")
}

// MARK: - pin3.riv を表示する

struct Pin2View: View {
    var isPlaying = true    // false のときは止めた絵として表示
    var isSelected = false  // タップされているか(true になった瞬間に回転の合図を送る)
    var isLive = false      // 開催中か(pin3.riv の isLooping に入れて、開催中の分岐(回転のループ)に切り替える)

    // 枠の下のあき(足元がイベントの場所に来るように、下にはみ出させる量)
    // pin3.riv の絵の足元が枠のいちばん下なら 0。ずれていたらここを調整する
    static let emptyBottomRatio: CGFloat = 0

    // 地図でのふだんの大きさ(pt)。ズームインすると最大2倍になる(48 → 96)
    // ・指で押しやすい最小の大きさ(44pt)より少し大きくしている
    // ・ちんちゃん(80pt)は絵が枠の一部にしか描かれていないが、pin3.riv は正方形いっぱいに描かれているので小さめにする
    static let baseSize: CGFloat = 48

    // ピンの色(pin3.riv の ViewModel の色の項目に入れる)
    // ・ふだんも開催中も同じ色(開催中は回転で見分ける)
    // ・キー:Rive エディタで付けた項目の名前 / 値:色
    // ・Rive に無い項目は飛ばすので、項目を足したらここに1行足すだけでよい
    static let pinColors: [String: UIColor] = [
        "centerColor":    UIColor(red: 1.00, green: 0.48, blue: 0.10, alpha: 1),   // 中心 #FF7A1A
        "pinBottomColor": UIColor(red: 1.00, green: 0.23, blue: 0.19, alpha: 1),   // 下の部分 #FF3B30
        "bodyColor":      UIColor(red: 0.00, green: 0.59, blue: 1.00, alpha: 1),   // 枠 #0096FF
    ]

    @StateObject private var riveVM: RiveViewModel
    @State private var pauseToken = 0   // 止める予約の番号(後から動かしたら、古い予約は無視する)

    init(isPlaying: Bool = true, isSelected: Bool = false, isLive: Bool = false) {
        self.isPlaying = isPlaying
        self.isSelected = isSelected
        self.isLive = isLive
        _riveVM = StateObject(wrappedValue: Self.makeViewModel())
    }

    private static func makeViewModel() -> RiveViewModel {
        if let file = Pin2Rive.file {
            return RiveViewModel(RiveModel(riveFile: file), stateMachineName: "State Machine 1")
        }
        return RiveViewModel(fileName: "pin3", stateMachineName: "State Machine 1")
    }

    var body: some View {
        riveVM.view()
            .onAppear {
                // ファイルの中の ViewModel につなぐ(回転の合図を送るのに必要)
                riveVM.riveModel?.enableAutoBind { _ in
                    applyColors()       // つながったら、色と
                    applyLive(isLive)   // 開催中かどうかを入れる
                }
                applyColors()
                applyLive(isLive)
                if isSelected { spin() }
                if !isPlaying { pauseSoon() }
            }
            .onChange(of: isSelected) { _, selected in
                if selected { spin() }
            }
            .onChange(of: isLive) { _, live in
                applyLive(live)
            }
            .onChange(of: isPlaying) { _, playing in
                if playing {
                    pauseToken += 1
                    riveVM.play()
                } else {
                    pauseSoon()
                }
            }
    }

    // pin3.riv の回転の合図(spinTrigger)を送る(名前は Rive エディタで付けた名前と同じにする)
    // ・Rive の作り方が2通りあるので、両方に対応する
    //   ① データバインディング(ViewModel の spinTrigger を、遷移の条件にしている)
    //   ② ステートマシンの Inputs(Inputs の欄に spinTrigger というトリガーを作っている)
    // pin3.riv の回転の合図(ステートマシンの Inputs の spinTrigger)を送る
    private func spin() {
        pauseToken += 1   // 回っている途中で止まらないように、止める予約は取り消す
        riveVM.play()
        riveVM.triggerInput("spinTrigger")
    }

    // 開催中かどうかを pin3.riv に入れる(true で開催中の分岐、false でふだんの分岐)
    // ・spinTrigger と同じく、① ViewModel の isLooping、② Inputs の isLooping の両方に対応する
    //   (今の pin3.riv はステートマシンの Inputs に isLooping がある)
    // 開催中かどうかを pin3.riv に入れる(ステートマシンの Inputs の isLooping)
    private func applyLive(_ live: Bool) {
        riveVM.setInput("isLooping", value: live)
    }

    // ピンの色を入れる
    private func applyColors() {
        guard let instance = riveVM.riveModel?.stateMachine?.viewModelInstance else { return }
        for (name, color) in Self.pinColors {
            instance.colorProperty(fromPath: name)?.value = color   // Rive に無い項目は何もしない
        }
    }

    // 少し描いてから止める(すぐ止めると、何も描かれないまま止まることがあるため)
    private func pauseSoon() {
        pauseToken += 1
        let token = pauseToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if token == pauseToken { riveVM.pause() }
        }
    }
}

// MARK: - 地図のピン用

// ・Rive は1つ作るのが重いので、起動直後に一斉に作らず、順番に作る(RiveSpawnQueue、TintyanPin.swift)
// ・動かすのは、開催中・タップ中などのピンだけ(animates)。それ以外は止めた絵
// ・タップしたピンは、少し大きくする
struct Pin2PinView: View {
    let animates: Bool
    let isSelected: Bool
    var isLive = false     // 開催中か(開催中の分岐に切り替える)
    var isPlaying = true   // マップのタブを表示中か

    @State private var isReady = false

    var body: some View {
        ZStack {
            if isReady {
                Pin2View(isPlaying: isPlaying && animates, isSelected: isSelected, isLive: isLive)
                    .scaleEffect(isSelected ? 1.25 : 1, anchor: .bottom)
                    .animation(.spring(response: 0.4, dampingFraction: 0.55), value: isSelected)
                    .transition(.opacity)
            }
        }
        .task {
            // タップしたときはすぐ出す。それ以外は順番待ちしてから作る
            if !isSelected {
                await RiveSpawnQueue.waitTurn()
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeOut(duration: 0.2)) { isReady = true }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        Pin2PinView(animates: true, isSelected: false)
            .frame(width: 100, height: 100)
        Pin2PinView(animates: true, isSelected: true)
            .frame(width: 100, height: 100)
    }
}
