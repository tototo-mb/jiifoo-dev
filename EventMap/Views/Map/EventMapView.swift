import SwiftUI
import MapKit

// ① 地図でイベントを見る画面（旧 CurrentlocationMapView）
struct EventMapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedEventID: Event.ID?
    @State private var showCreateEvent=false
    @AppStorage("showJoinableRange") private var showJoinableRange=true
    

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $cameraPosition, selection: $selectedEventID) {
                UserAnnotation()
                if showJoinableRange, let userLocation = locationManager.userLocation {
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
            //ScreenEdgeGlowView()

            // 読み込み中の表示(上部中央)
            if eventStore.isLoading {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
            }
            VStack(spacing: 12) {
                // 再読み込みボタン
                Button {
                    if let userLocation = locationManager.userLocation {
                        Task { await eventStore.load(near: userLocation, force: true) }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 50, height: 50)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 3)
                }
                //イベント作成ボタン
                Button {
                    showCreateEvent=true
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.blue)
                        .frame(width: 50, height: 50)
                        .background(.regularMaterial, in: Circle())
                        .shadow(radius: 3)
                }
                .disabled(locationManager.userLocation==nil)

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
            }
            .padding(.trailing, 16)
            .padding(.bottom, 24)
        }
        .task(id: locationKey) {
            if let userLocation = locationManager.userLocation {
                await eventStore.load(near: userLocation)
            }
        }
        // 予約結果やエラーのお知らせ
        .alert(eventStore.message ?? "", isPresented: Binding(
            get: { eventStore.message != nil && selectedEventID == nil && !showCreateEvent },
            set: { if !$0 { eventStore.message = nil } }
        )) {
            Button("OK", role: .cancel) { }
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
        // ＋ボタンが押されたら作成画面を表示   ← ここから追加
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
                .environment(eventStore)
                .environment(locationManager)
        }
    }
    

    // ピン1つ分の見た目（body の外、EventMapView の中に置く）
    //法人ならBusinessPin、個人ユーザーならPrivatePinを立てる
    
    
    // 現在地をおよそ100m単位に丸めた目印。これが変わったら読み込み直す
    private var locationKey: String {
        guard let l = locationManager.userLocation else { return "none" }
        return String(format: "%.3f,%.3f", l.latitude, l.longitude)
    }
    @ViewBuilder
    private func eventPin(for event: Event) -> some View {
        let joinable = locationManager.isJoinable(event.coordinate)
        Group{
            if event.scale == .businessMode{
                BusinessPinView(isJoinable: joinable)
            }else{
                PrivatePinView(isJoinable: joinable)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture{
            selectedEventID=event.id
        }
    }
}

#Preview {
    EventMapView()
        .environment(LocationManager())
        .environment(EventStore(events: sampleEvents))
}
