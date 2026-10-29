import SwiftUI
import MapKit

// 「マップ上から選択」で開く、集合場所を選ぶための全画面の地図
// タップした場所にピンを立て、「決定」で作成画面に戻る
struct PlacePickerMapView: View {
    @Binding var coordinate: CLLocationCoordinate2D?        // 作成画面の「選んだ場所」
    var limitToNearby: Bool = true                          // true なら現在地から 800m 以内だけ選べる(個人)
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition
    @State private var tempCoordinate: CLLocationCoordinate2D?   // 決定するまでの仮の場所

    init(coordinate: Binding<CLLocationCoordinate2D?>, limitToNearby: Bool = true) {
        _coordinate = coordinate
        self.limitToNearby = limitToNearby
        _tempCoordinate = State(initialValue: coordinate.wrappedValue)
        // すでに選んだ場所があればそこを、なければ現在地を表示する
        if let current = coordinate.wrappedValue {
            _position = State(initialValue: .region(MKCoordinateRegion(
                center: current, latitudinalMeters: 800, longitudinalMeters: 800)))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    // 選べる範囲(現在地から 800m)。法人のときは表示しない
                    if limitToNearby, let user = locationManager.userLocation {
                        MapCircle(center: user, radius: LocationManager.joinableRadius)
                            .foregroundStyle(.blue.opacity(0.08))
                            .stroke(.blue.opacity(0.5), lineWidth: 1.5)
                    }

                    if let tempCoordinate {
                        Marker("集合場所", coordinate: tempCoordinate)
                            .tint(.red)
                    }
                }
                .onTapGesture { point in
                    // タップした画面上の位置を、地図の座標に変える
                    if let tapped = proxy.convert(point, from: .local) {
                        tempCoordinate = tapped
                    }
                }
            }
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(isTooFar ? .red : .primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
            .navigationTitle("マップ上から選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        coordinate = tempCoordinate   // 作成画面に場所を渡す
                        dismiss()
                    }
                    .disabled(tempCoordinate == nil || isTooFar)
                }
            }
        }
    }

    // 個人のとき、仮の場所が現在地から 800m より遠いか
    private var isTooFar: Bool {
        guard limitToNearby, let tempCoordinate,
              let distance = locationManager.distance(to: tempCoordinate) else { return false }
        return distance > LocationManager.joinableRadius
    }

    private var message: String {
        if tempCoordinate == nil { return "集合場所をタップしてください" }
        if isTooFar { return "現在地から\(Int(LocationManager.joinableRadius))m以内をタップしてください" }
        return "ピンを立てました。タップで位置を直せます"
    }
}

#Preview {
    PlacePickerMapView(coordinate: .constant(nil))
        .environment(LocationManager())
}
