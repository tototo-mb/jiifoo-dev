import SwiftUI
import MapKit

// 全国のイベントマップ(地図の地球儀ボタンから開く)
// 日本全体を見渡す簡易的な地図。近づきすぎないように、ズームできる範囲を決めている
struct FarEventsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager

    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var selectedEvent: Event?
    @State private var cameraPosition: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: Self.japanCenter, distance: 3_500_000,
        heading: 0, pitch: 0)
    )
    //最初に写し出す場所(最終的には現在地付近を表示)    
    static let japanCenter = CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7)

    //ズームの制限
    static let japanBounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7),
        span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 23)
        ),
        minimumDistance: 30_000, //高さ30kmまでズーム可能
        maximumDistance: 4_000_000 
    )
    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition, bounds: Self.japanBounds) {
                ForEach(events) { event in
                    Annotation(event.title, coordinate: event.coordinate) {
                        eventDot(for: event)
                    }
                    .annotationTitles(.hidden) //点の下にイベント名を出さない（イベントピン重複回避）
                }
            }
            //店名を非表示
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .mapControls {}
            .overlay {
                if isLoading {
                    ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                }
            }
            .navigationTitle("全国のイベント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task {
                await loadEvents()
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, showMapButton: true)
                    .environment(eventStore)
                    .environment(locationManager)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    //イベント一つ分の点（法人はオレンジ、個人ユーザーは青）
    private func eventDot(for event: Event) -> some View {
        Circle()
            .fill(event.scale == .businessMode ? Color.orange : Color.blue)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
            .onTapGesture {
                selectedEvent = event
            }
    }

    //全国の募集中イベントを読み込む（現在地から近い順に100件表示）
    private func loadEvents() async {
        let center = locationManager.userLocation ?? Self.japanCenter
        isLoading = true
        defer { isLoading = false }
        do {
            let pins = try await JiifooAPI.searchEvents(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusM: nil)
            events = pins.map(Event.init(pin:))
        } catch {
            print("イベントの読み込みに失敗しました",error)
        }
    }
}