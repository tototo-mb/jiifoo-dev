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
    @State private var searchText = ""                  // 地点検索の入力
    @State private var searchResults: [MKMapItem] = []   // 検索で見つかった場所
    @State private var searchedPlace: MKMapItem?          // 選んだ場所(地図に印を出す)
    @State private var showList = false                   // 一覧を出すか
    @State private var listSelectedEvent: Event?          // 一覧で選んだイベント(詳細を出す)

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
                // 現在地(青い丸)
                UserAnnotation()
                // 検索で選んだ場所の印
                if let searchedPlace {
                    Marker(item: searchedPlace)
                        .tint(.red)
                }
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
            // 地点検索(地名や駅名で探す)
            .searchable(text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "地名・駅名で探す")
            .onSubmit(of: .search) {
                Task { await searchPlaces() }
            }
            // 入力を消したら、候補と印も消す
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    searchResults = []
                    searchedPlace = nil
                }
            }
            // 検索結果の一覧(選ぶとその場所へ移動)
            .overlay(alignment: .top) {
                if !searchResults.isEmpty {
                    searchResultList
                }
            }
            .keyboardCloseButton()
            // 場所を選んだら「リストで見る」ボタンを出す
            .overlay(alignment: .bottomLeading) {
                if searchedPlace != nil {
                    Button {
                        showList = true
                    } label: {
                        Label("リストで見る(\(events.count)件)", systemImage: "list.bullet")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.regularMaterial, in: Capsule())
                            .shadow(radius: 3)
                    }
                    .padding(.leading, 16)
                    .padding(.bottom, 24)
                }
            }
            // 地図に写っているイベントの一覧
            .sheet(isPresented: $showList) {
                eventListSheet
                    .presentationDetents([.medium, .large])
            }
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

    // MARK: - 地点検索

    // 日本のあたり(検索で日本の場所が先に出るように)
    static let japanRegion = MKCoordinateRegion(
        center: japanCenter,
        span: MKCoordinateSpan(latitudeDelta: 22, longitudeDelta: 23))

    // 入力した言葉で場所を探す
    private func searchPlaces() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = Self.japanRegion
        request.resultTypes = [.address, .pointOfInterest]
        let response = try? await MKLocalSearch(request: request).start()
        searchResults = response?.mapItems ?? []
    }

    // 選んだ場所へ地図を動かす
    private func moveTo(_ place: MKMapItem) {
        searchedPlace = place
        searchResults = []
        cameraPosition = .camera(MapCamera(centerCoordinate: place.placemark.coordinate,
                                           distance: 20_000,
                                           heading: 0,
                                           pitch: 0))
    }

    // 検索結果の一覧
    private var searchResultList: some View {
        List(searchResults, id: \.self) { place in
            Button {
                moveTo(place)
            } label: {
                VStack(alignment: .leading) {
                    Text(place.name ?? "名前のない場所")
                        .foregroundStyle(.primary)
                    if let address = place.placemark.title {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 4)
        .padding(.horizontal, 12)
    }

    // MARK: - 一覧

    // 一覧に出すイベント(選んだ場所から近い順)
    private var listEvents: [Event] {
        guard let center = searchedPlace?.placemark.coordinate else { return events }
        let place = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return events.sorted {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: place)
            < CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: place)
        }
    }

    // 一覧の画面
    private var eventListSheet: some View {
        NavigationStack {
            List(listEvents) { event in
                Button {
                    listSelectedEvent = event
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(event.placeName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(event.startsAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if listEvents.isEmpty {
                    ContentUnavailableView("この範囲にイベントはありません",
                                           systemImage: "mappin.slash")
                }
            }
            .navigationTitle("\(searchedPlace?.name ?? "")付近のイベント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { showList = false }
                }
            }
            // 一覧で選んだイベントの詳細(「マップで場所を見る」でこの地図へ戻る)
            .sheet(item: $listSelectedEvent) { event in
                EventDetailView(event: event, showMapButton: true, onShowMap: {
                    showOnMap(event)
                })
                .environment(eventStore)
                .environment(locationManager)
                .presentationDetents([.medium, .large])
            }
        }
    }

    // 一覧を閉じて、そのイベントの場所へ地図を動かす
    private func showOnMap(_ event: Event) {
        listSelectedEvent = nil
        showList = false
        cameraPosition = .camera(MapCamera(centerCoordinate: event.coordinate,
                                           distance: 5_000,
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