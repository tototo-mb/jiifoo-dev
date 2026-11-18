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
    @State private var loadTask: Task<Void, Never>? //実行中の再読み込み
    @State private var cameraPosition: MapCameraPosition 

    //startCamera:開いた時に映す場所と高さ（イベントマップと同じ）
    private let startCamera: MapCamera?

    init(startCamera: MapCamera? = nil) {
        self.startCamera = startCamera
        let camera = startCamera
            ?? MapCamera(centerCoordinate: Self.japanCenter, distance: 3_500_000, heading:0, pitch: 0)
        _cameraPosition = State(initialValue: .camera(camera))
    }
    //最初に写し出す場所(最終的には現在地付近を表示)    
    static let japanCenter = CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7)

    //一度に読み込むことのできるイベントの最大数
    static let maxCount = 100
    //ズームの制限
    static let japanBounds = MapCameraBounds(
        centerCoordinateBounds: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6, longitude: 139.7),
        span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 23)
        ),
        minimumDistance: 5_000, //高さ5kmまでズーム可能
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
            //地図を動かし終わったら、写っている範囲のイベントを表示
            .onMapCameraChange(frequency: .onEnd) { context in 
                loadTask?.cancel()
                loadTask = Task {
                    await loadEvents(in: context.region)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                }
            }
            //１００件以上の表示しきれない数のイベントがあった時
            .overlay(alignment: .top) {
                if events.count >= Self.maxCount {
                    Text("表示しきれないイベントがあります。拡大すると表示されます")
                    .font(.footnote)
                    .padding(.horizontal,12)
                    .padding(.vertical,8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top,8)
                }
            }
            .navigationTitle("全国のイベント")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    moveToCurrentLocation()
                } label: {
                    Image(systemName: "location")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 50, height: 50)
                    .background(.regularMaterial, in: Circle())
                    .shadow(radius: 3)
                }
                .disabled(locationManager.userLocation == nil) //現在地がわかるまで押せないようにする
                .padding(.trailing,16)
                .padding(.bottom,24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, showMapButton: true)
                    .environment(eventStore)
                    .environment(locationManager)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    //現在地へ戻る
    private func moveToCurrentLocation() {
        guard let here = locationManager.userLocation else { return }
            cameraPosition = .camera(MapCamera(centerCoordinate: here,
                                                distance: startCamera?.distance ?? 5_000,
                                                heading: 0,
                                                pitch: 0))
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

    //
    private func loadEvents(in region: MKCoordinateRegion) async {
        //
        let center = region.center
        let corner = CLLocation(latitude: center.latitude + region.span.latitudeDelta / 2,
                                longitude: center.longitude + region.span.longitudeDelta / 2)
        let radius = CLLocation(latitude: center.latitude, longitude: center.longitude)
            .distance(from: corner)

        isLoading = true
        do {
            let pins = try await JiifooAPI.searchEvents(
                latitude: center.latitude,
                longitude: center.longitude,
                radiusM: radius)
            guard !Task.isCancelled else { return }
            events = pins.map(Event.init(pin:))
        } catch {
            guard !Task.isCancelled else { return }
            print("イベントの読み込みに失敗しました",error)
        }
        isLoading = false
    }
}