import SwiftUI
import MapKit
import RiveRuntime

// Rive ファイルの表示テスト(設定画面の「開発用」から開く)
// tintyan.riv の大きさ・長さなどをスライダーで細かく変えて、地図の上での見え方を確かめる
// ※ ちょうどよい数値が決まったら、この画面と設定画面の入口は消す
struct RiveTestView: View {
    @State private var values = TintyanValues()
    @State private var pinSize: CGFloat = 80          // 地図に置くときの枠の大きさ(ポイント)
    @State private var mapDistance: Double = EventMapView.maxZoomOutDistance   // 地図の高さ(m)。はじめはマップ画面のいちばん引いた高さ
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
                            // 足元が地図の場所に来るように、下の空きの分だけ下にはみ出させる
                            .padding(.bottom, -pinSize * TintyanView.emptyBottomRatio)
                    }
                    // 比べる用:今の炎のピン(個人)
                    Annotation("", coordinate: fireCenter, anchor: .bottom) {
                        PrivatePinView(isJoinable: true)
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 320)
                .listRowInsets(EdgeInsets())
                valueSlider("地図の高さ(m)", value: $mapDistance, range: 300...EventMapView.maxZoomOutDistance, step: 50)                
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
                
                valueSlider("縁取りの太さ hutidori", value: $values.outlineWidth, range: 0...20, step: 0.5)
                ColorPicker("体の色 bodycolor", selection: $values.bodyColor, supportsOpacity: false)
                ColorPicker("体のふちの色 bodysidecolor", selection: $values.bodySideColor, supportsOpacity: false)
                ColorPicker("縁取りの色 huticolor", selection: $values.outlineColor, supportsOpacity: false)
                ColorPicker("砂の色 sandcolor", selection: $values.sandColor, supportsOpacity: false)
                ColorPicker("穴の色 holecolor", selection: $values.holeColor, supportsOpacity: false)
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
    private func valueSlider<V: BinaryFloatingPoint>(
        _ title: String, value: Binding<V>,
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



