import SwiftUI
import MapKit
import RiveRuntime

// Rive ファイルの表示テスト(設定画面の「開発用」から開く)
// tintyan.riv の大きさ・長さなどをスライダーで細かく変えて、地図の上での見え方を確かめる
// ※ ちょうどよい数値が決まったら、この画面と設定画面の入口は消す
struct RiveTestView: View {
    @State private var values = TintyanValues()
    @State private var pinSize: CGFloat = 80          // 地図に置くときの枠の大きさ(ポイント)
    @State private var mapDistance: Double = 1500     // 地図の高さ(m)。小さいほど寄る

    // 地図に置く場所(渋谷駅のあたり)と、比べるための炎のピンの場所
    private let center = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7005)
    private let fireCenter = CLLocationCoordinate2D(latitude: 35.6595, longitude: 139.7030)

    var body: some View {
        List {
            // ---- 地図で見る ----
            Section {
                Map(position: .constant(.camera(MapCamera(centerCoordinate: center,
                                                          distance: mapDistance,
                                                          heading: 0, pitch: 0)))) {
                    Annotation("", coordinate: center, anchor: .bottom) {
                        TintyanView(values: values)
                            .frame(width: pinSize, height: pinSize)
                    }
                    // 比べる用:今の炎のピン(個人)
                    Annotation("", coordinate: fireCenter, anchor: .bottom) {
                        PrivatePinView(isJoinable: true)
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 320)
                .listRowInsets(EdgeInsets())

                valueSlider("地図の高さ(m)", value: $mapDistance, range: 300...4000, step: 50)
                valueSlider("地図に置く枠の大きさ", value: $pinSize, range: 30...200, step: 1)
            } header: {
                Text("地図で見る(右は今の炎のピン)")
            }

            // ---- 大きく見る ----
            Section("大きく見る") {
                TintyanView(values: values)
                    .frame(height: 220)
            }

            // ---- 数値 ----
            Section {
                valueSlider("体の縦 bodytate", value: $values.bodyTate, range: 0...400, step: 1)
                valueSlider("体の横 bodyyoko", value: $values.bodyYoko, range: 0...150, step: 1)
                valueSlider("砂の縦 sandtate", value: $values.sandTate, range: 0...150, step: 1)
                valueSlider("砂の横 sandyoko", value: $values.sandYoko, range: 0...300, step: 1)
                valueSlider("揺れの幅 swayswidth", value: $values.swayWidth, range: 0...60, step: 0.5)
                valueSlider("揺れの速さ swaysspead", value: $values.swaySpeed, range: 0...10, step: 0.1)
                valueSlider("うねりの強さ wavestrength", value: $values.waveStrength, range: 0...60, step: 0.5)
                valueSlider("うねりの幅 wavewidth", value: $values.waveWidth, range: 0...60, step: 0.5)
                valueSlider("うねりの速さ wavespead", value: $values.waveSpeed, range: 0...10, step: 0.1)
                Button("はじめの数値に戻す") { values = TintyanValues() }
            } header: {
                Text("数値")
            } footer: {
                // 決まった数値を書き写せるように、まとめて表示する(長押しでコピーできる)
                Text(values.summary + "\n枠の大きさ \(Int(pinSize))")
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Rive のテスト")
        .navigationBarTitleDisplayMode(.inline)
    }

    // 名前・今の数値・スライダーを1行にまとめた部品
    private func valueSlider<V: BinaryFloatingPoint>(_ title: String, value: Binding<V>,
                                                    range: ClosedRange<V>, step: V.Stride) -> some View
    where V.Stride: BinaryFloatingPoint {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%.1f", Double(value.wrappedValue)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}

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

    // まとめて書き写す用の文字
    var summary: String {
        String(format: "体 縦%.0f 横%.0f / 砂 縦%.0f 横%.0f / 揺れ 幅%.1f 速さ%.1f / うねり 強さ%.1f 幅%.1f 速さ%.1f",
               bodyTate, bodyYoko, sandTate, sandYoko, swayWidth, swaySpeed, waveStrength, waveWidth, waveSpeed)
    }
}

// tintyan.riv を、数値を入れて表示する(数値が変わったらすぐ反映)
struct TintyanView: View {
    let values: TintyanValues

    @StateObject private var riveVM = RiveViewModel(
        fileName: "tintyan",
        stateMachineName: "State Machine 1"
    )

    var body: some View {
        riveVM.view()
            .onAppear {
                // ファイルの中の ViewModel につないで、つながったら数値を入れる
                riveVM.riveModel?.enableAutoBind { _ in
                    applyValues()
                }
                applyValues()
            }
            .onChange(of: values) {
                applyValues()
            }
    }

    // Rive の ViewModel に数値を入れる(名前は Rive エディタで付けた名前と同じにする)
    private func applyValues() {
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
    }
}