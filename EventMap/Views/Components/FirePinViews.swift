import SwiftUI
import RiveRuntime

//法人ユーザー用ピン
struct BusinessPinView: View {
    let isJoinable: Bool

    @StateObject private var riveViewModel1 = RiveViewModel(
        fileName: "Fire",
        stateMachineName: "State Machine 1",
        artboardName: "FireParticleSystem"
    )

@State private var isLoaded=false
    
    var body: some View {
        riveViewModel1.view()
            .frame(width: 60, height: 60)
            .saturation(isJoinable ? 1 : 0)
            .opacity(isJoinable ? 1 : 0.6)
    }
}

struct PrivatePinView:View{
    let isJoinable: Bool
    
    @StateObject private var riveViewModel2 = RiveViewModel(
        fileName:"dopa_fire",
        stateMachineName:"State Machine 1",
        artboardName:"FireParticleSystem"
    )
    
@State private var isLoaded=false
    
    var body:some View{
        riveViewModel2.view()
            .frame(width: 60, height: 60)
            .saturation(isJoinable ? 1 : 0)
            .opacity(isJoinable ? 1 : 0.6)
    }
}

// 色やサイズの設定はここを書き換える
enum FirePinStyle {
    case normal   // 通常時
    case selected // 選択中
    case live     // 開催中(開始時刻を過ぎたイベント)

    var size: Float {
        switch self {
        case .normal:   return 45
        case .selected: return 75
        case .live:     return 45
        }
    }

    var height: Float {
        switch self {
        case .normal:   return 55
        case .selected: return 70
        case .live:     return 55
        }
    }

    var startColor: UIColor {
        switch self {
        case .normal:   return .orange // 通常時の根元の色
        case .selected: return .cyan   // 選択中の根元の色
        case .live:     return .yellow // 開催中の根元の色
        }
    }

    var endColor: UIColor {
        switch self {
        case .normal:   return .red    // 通常時の先端の色
        case .selected: return .blue   // 選択中の先端の色
        case .live:     return .orange // 開催中の先端の色
        }
    }
}

// マップに置く炎ピン本体(fire_pin.riv。色と大きさを FirePinStyle で変えられる)
struct FirePinView: View {
    let style: FirePinStyle
    let onTap: () -> Void

    // Riveから書き出したファイル名(stateMachineName: nil で、ファイルの最初のステートマシンを使う)
    @StateObject private var riveVM = RiveViewModel(
        fileName: "fire_pin",
        stateMachineName: nil
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            // 1. 炎の見た目(タップ判定は完全にオフ)
            riveVM.view()
                .background(SwiftUI.Color.clear)
                .frame(width: 120, height: 120)
                .allowsHitTesting(false)

            // 2. タップ判定専用の透明な枠(炎の根元だけに配置)
            SwiftUI.Color.clear
                .frame(width: 44, height: 50)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap()
                }
        }
        .onAppear {
            // ファイルの最初の ViewModel を自動でつなぎ、つながったら色と大きさを送る
            riveVM.riveModel?.enableAutoBind { _ in
                applyStyle()
            }
            applyStyle()
        }
        .onChange(of: style) {
            applyStyle()
        }
    }

    // RiveのViewModelへサイズと色を送る処理
    private func applyStyle() {
        guard let instance = riveVM.riveModel?.stateMachine?.viewModelInstance else { return }
        instance.numberProperty(fromPath: "ookisa")?.value = style.size
        instance.numberProperty(fromPath: "tatenaga")?.value = style.height
        instance.colorProperty(fromPath: "nemoto")?.value = style.startColor
        instance.colorProperty(fromPath: "saki")?.value = style.endColor
    }
}


#Preview {
    BusinessPinView(isJoinable: true)
    PrivatePinView(isJoinable: true)
}

