// Views/Map/MapOrbitCamera.swift
import SwiftUI
import MapKit

struct MapOrbitCameraModifier<ID: Equatable>: ViewModifier {
    let id: ID?                          // 選択中のイベントのID
    let coordinate: CLLocationCoordinate2D?
    var distance: Double = 800           // 近づく距離(m)
    var pitch: Double = 60               // 傾き(度)
    var rotation: Double = 120           // 横に回り込む角度(360で一周)

    @State private var trigger = false

    func body(content: Content) -> some View {
        content
            .mapCameraKeyframeAnimator(trigger: trigger) { initial in
                let center = coordinate ?? initial.centerCoordinate

                KeyframeTrack(\MapCamera.centerCoordinate) {
                    CubicKeyframe(center, duration: 2)
                    CubicKeyframe(center, duration: 8)
                }
                KeyframeTrack(\MapCamera.pitch) {
                    CubicKeyframe(pitch, duration: 2)
                    CubicKeyframe(pitch, duration: 8)
                }
                KeyframeTrack(\MapCamera.distance) {
                    CubicKeyframe(distance, duration: 2)
                    CubicKeyframe(distance, duration: 8)
                }
                KeyframeTrack(\MapCamera.heading) {
                    CubicKeyframe(initial.heading, duration: 2)
                    LinearKeyframe(initial.heading + rotation, duration: 8)
                }
            }
            .onChange(of: id) { _, newValue in
                guard newValue != nil, coordinate != nil else { return }
                trigger.toggle()
            }
    }
}

extension View {
    func orbitCamera<ID: Equatable>(on id: ID?,
                                    coordinate: CLLocationCoordinate2D?) -> some View {
        modifier(MapOrbitCameraModifier(id: id, coordinate: coordinate))
    }
}
