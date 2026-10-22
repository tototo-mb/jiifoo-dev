import SwiftUI
import MapKit

// ① 地図でイベントを見る画面（旧 CurrentlocationMapView）
struct EventMapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedEventID: Event.ID?
    

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition, selection: $selectedEventID) {
                UserAnnotation()
                if let userLocation = locationManager.userLocation {
                    MapCircle(center: userLocation, radius: LocationManager.joinableRadius)
                        .foregroundStyle(.blue.opacity(0.08))
                        .stroke(.blue.opacity(0.5), lineWidth: 1.5)
                }

                ForEach(eventStore.events) { event in
                    Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
                        eventPin(for: event)
                    }
                }
            }
            .mapControls { }
            .mapStyle(.standard(elevation: .realistic,
                                emphasis: .muted,
                                pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
            ScreenEdgeGlowView()
            // 現在地ボタン（右下）
            Button {
                withAnimation {
                    cameraPosition = .userLocation(fallback: .automatic)
                }
            } label: {
                Image(systemName: cameraPosition.followsUserLocation ? "location.fill" : "location")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 3)
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .onChange(of: locationManager.authorizationStatus) { _, status in
            // 許可されたら改めて現在地へカメラを合わせる
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                cameraPosition = .userLocation(fallback: .automatic)
            }
        }
        // ピンが選択されたら詳細シートを表示
        .sheet(item: Binding(
            get: { eventStore.events.first { $0.id == selectedEventID } },
            set: { if $0 == nil { selectedEventID = nil } }   // 閉じたら選択解除
        )) { event in
            EventDetailView(event: event)
                .environment(eventStore)
                .environment(locationManager)
                .presentationDetents([.medium, .large])
        }
    }

    // ピン1つ分の見た目（body の外、EventMapView の中に置く）
    private func eventPin(for event: Event) -> some View {
        let joinable = locationManager.isJoinable(event.coordinate)
        return FirePinView(isJoinable: joinable)
            .contentShape(Rectangle())
            .onTapGesture {
                selectedEventID = event.id   // タップで詳細シートを開く
            }
    }
}

#Preview {
    EventMapView()
        .environment(LocationManager())
        .environment(EventStore())
}
