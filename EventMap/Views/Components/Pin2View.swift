import SwiftUI
import RiveRuntime

// 新しいピン(pin2.riv)と、ピンの種類の切り替え
// ・ふだんは新しいピン。設定画面の「ピンの種類」で、旧ピン(ちんちゃん)に切り替えられる
// ・pin2.riv は数値を受け取らないアニメーションなので、
//   タップしたときは少し大きくし、開催中は足元の波紋(LivePinEffect)で目立たせる

// MARK: - ピンの種類

enum PinStyle: String, CaseIterable, Identifiable {
    case pin2      // 新しいピン(pin2.riv)
    case tintyan   // 旧ピン(ちんちゃん、tintyan.riv)

    // 設定に保存するときの名前(@AppStorage で使う)
    static let storageKey = "pinStyle"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pin2:    return "新しいピン"
        case .tintyan: return "ちんちゃん(旧ピン)"
        }
    }
}

// MARK: - pin2.riv の読み込み(アプリ全体で1回だけ)

// ※ 起動時に裏のスレッドで読み込むので、メインスレッド専用(MainActor)にしない
nonisolated enum Pin2Rive {
    nonisolated(unsafe) static let file: RiveFile? = try? RiveFile(name: "pin2")
}

// MARK: - pin2.riv を表示する

struct Pin2View: View {
    var isPlaying = true   // false のときは止めた絵として表示

    // 枠の下のあき(足元がイベントの場所に来るように、下にはみ出させる量)
    // pin2.riv の絵の足元が枠のいちばん下なら 0。ずれていたらここを調整する
    static let emptyBottomRatio: CGFloat = 0

    // 地図でのふだんの大きさ(pt)。ズームインすると最大2倍になる(48 → 96)
    // ・指で押しやすい最小の大きさ(44pt)より少し大きくしている
    // ・ちんちゃん(80pt)は絵が枠の一部にしか描かれていないが、pin2.riv は正方形いっぱいに描かれているので小さめにする
    static let baseSize: CGFloat = 48

    @StateObject private var riveVM: RiveViewModel
    @State private var pauseToken = 0   // 止める予約の番号(後から動かしたら、古い予約は無視する)

    init(isPlaying: Bool = true) {
        self.isPlaying = isPlaying
        _riveVM = StateObject(wrappedValue: Self.makeViewModel())
    }

    private static func makeViewModel() -> RiveViewModel {
        if let file = Pin2Rive.file {
            return RiveViewModel(RiveModel(riveFile: file), stateMachineName: "State Machine 1")
        }
        return RiveViewModel(fileName: "pin2", stateMachineName: "State Machine 1")
    }

    var body: some View {
        riveVM.view()
            .onAppear {
                if !isPlaying { pauseSoon() }
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
    var isPlaying = true   // マップのタブを表示中か

    @State private var isReady = false

    var body: some View {
        ZStack {
            if isReady {
                Pin2View(isPlaying: isPlaying && animates)
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
