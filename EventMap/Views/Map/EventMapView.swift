import SwiftUI
import MapKit

// ① 地図でイベントを見る画面（旧 CurrentlocationMapView）
struct EventMapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedEventID: Event.ID?
    @State private var showCreateEvent=false
    @State private var lastCamera: MapCamera?
    @State private var cameraTask: Task<Void, Never>?   // 実行中のカメラの動き
    @State private var isReturningHome = false          // 現在地へ戻っている最中
    @State private var savedCamera: MapCamera?          // ピンを押す前のカメラ
    @State private var wasFollowing = false             // ピンを押す前に追従中だったか
    @State private var mapProxy: MapProxy?              // 画面の位置 ⇔ 地図の座標の変換用
    @State private var measuredOffset: Double?          // 実際の画面で測ったずらし量(m)
    

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MapReader { proxy in
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
                                    pointsOfInterest: .including([
                                        .publicTransport,   // 駅・バス停
                                        .park,              // 公園
                                        .landmark,          // ランドマーク
                                        .castle,            // 城・史跡
                                        .stadium,           // スタジアム・競技場
                                        .university,        // 大学
                                        .police,             // 交番・警察
                                        .museum,
                                        .theater
                                    ])))
                .onMapCameraChange(frequency: .onEnd) { context in
                    lastCamera = context.camera
                    Task { await eventStore.load(near: context.region.center) }
                }
                .ignoresSafeArea()
                .onAppear { mapProxy = proxy }
            }
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
                .disabled(locationManager.userLocation == nil)   // 現在地がわかるまで押せない

                // 現在地ボタン（右下）
                Button {
                    backTo2D()
                } label: {
                    Image(systemName: (cameraPosition.followsUserLocation || isReturningHome) ? "location.fill" : "location")
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
        // およそ100m動くたびに読み込みを試す(実際の読み込みは300m以上動いたときだけ)
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
        // 詳細シートを閉じたら、ピンを押す前の場所に戻る
        .onChange(of: selectedEventID) { _, newValue in
            if newValue == nil {
                returnToSavedCamera()
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
        // 「+」でイベント作成画面を表示
        .sheet(isPresented: $showCreateEvent) {
            CreateEventView()
                .environment(eventStore)
                .environment(locationManager)
        }
    }

    // ピン1つ分の見た目（body の外、EventMapView の中に置く）
    //法人ならBusinessPin、個人ユーザーならPrivatePinを立てる
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
            // ピンを押す前のカメラを記録（2回目以降のタップでは上書きしない）
            if savedCamera == nil {
                savedCamera = lastCamera
                wasFollowing = cameraPosition.followsUserLocation
            }
            selectedEventID=event.id
            flyToEvent(event)
        }
    }

    // MARK: - 3Dカメラ
    // 現在地をおよそ100m単位に丸めた値。これが変わると .task が動き直す
    private var locationKey: String {
        guard let location = locationManager.userLocation else { return "none" }
        return String(format: "%.3f,%.3f", location.latitude, location.longitude)
    }

    private let orbitDistance: Double = 800   // 近づく距離(m)
    private let orbitPitch: Double = 60       // 傾き(度)
    private let orbitStep: Double = 15        // 1回で回る角度(度)
    private let orbitSeconds: Double = 3.3    // 1回にかける秒数（大きいほどゆっくり）
    private let pinScreenRatio: CGFloat = 0.25 // ピンを置きたい位置（上から1/4）

    // ピンを選んだとき：斜めから寄る → ゆっくり回り続ける
    private func flyToEvent(_ event: Event) {
        cameraTask?.cancel()   // 前の動きを止める
        let startHeading = lastCamera?.heading ?? 0

        cameraTask = Task { @MainActor in
            // ① 斜めから寄る
            withAnimation(.easeInOut(duration: 2)) {
                cameraPosition = .camera(orbitCamera(around: event.coordinate, heading: startHeading))
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }

            // 初回だけ：実際の画面で位置を測って、ピンが上から1/4に来るよう微調整
            if measuredOffset == nil, let proxy = mapProxy {
                let screen = UIScreen.main.bounds.size
                let target = CGPoint(x: screen.width / 2, y: screen.height * pinScreenRatio)
                if let ground = proxy.convert(target, from: .global) {
                    let forward = forwardMeters(from: event.coordinate, to: ground, heading: startHeading)
                    measuredOffset = currentOffset + forward
                    withAnimation(.easeInOut(duration: 0.6)) {
                        cameraPosition = .camera(orbitCamera(around: event.coordinate, heading: startHeading))
                    }
                    try? await Task.sleep(for: .seconds(0.6))
                }
            }

            // ② キャンセルされるまでゆっくり回転
            var heading = startHeading
            while !Task.isCancelled {
                heading += orbitStep
                withAnimation(.linear(duration: orbitSeconds)) {
                    cameraPosition = .camera(orbitCamera(around: event.coordinate, heading: heading))
                }
                try? await Task.sleep(for: .seconds(orbitSeconds))
            }
        }
    }

    // 今のずらし量（測る前は仮の値）
    private var currentOffset: Double { measuredOffset ?? 300 }

    // ピンが画面の上側に見えるカメラを作る（向いている方向の手前へ中心をずらす）
    private func orbitCamera(around coordinate: CLLocationCoordinate2D, heading: Double) -> MapCamera {
        let rad = (heading + 180) * .pi / 180
        let dLat = currentOffset * cos(rad) / 111_000
        let dLon = currentOffset * sin(rad) / (111_000 * cos(coordinate.latitude * .pi / 180))
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                            longitude: coordinate.longitude + dLon)
        return MapCamera(centerCoordinate: center,
                         distance: orbitDistance,
                         heading: heading,
                         pitch: orbitPitch)
    }

    // from から to が、向いている方向に何m先にあるか
    private func forwardMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, heading: Double) -> Double {
        let north = (to.latitude - from.latitude) * 111_000
        let east = (to.longitude - from.longitude) * 111_000 * cos(from.latitude * .pi / 180)
        let rad = heading * .pi / 180
        return north * cos(rad) + east * sin(rad)
    }

    // 詳細を閉じたとき：ピンを押す前のカメラへ戻る
    private func returnToSavedCamera() {
        guard let saved = savedCamera else { return }
        let follow = wasFollowing
        savedCamera = nil

        cameraTask?.cancel()   // 回転を止める
        if follow { isReturningHome = true }

        cameraTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 1.5)) {
                cameraPosition = .camera(saved)
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            // 追従中だった場合は追従モードに戻す（傾きは元の2Dのまま）
            if follow {
                cameraPosition = .userLocation(fallback: .automatic)
            }
            isReturningHome = false
        }
    }

    // 現在地ボタン：2D（真上・北が上）に戻して現在地追従へ
    private func backTo2D() {
        cameraTask?.cancel()
        savedCamera = nil      // 詳細を閉じたときの「元に戻る」は使わない
        selectedEventID = nil
        isReturningHome = true // 押した瞬間にアイコンを青く

        cameraTask = Task { @MainActor in
            if let userLocation = locationManager.userLocation {
                withAnimation(.easeInOut(duration: 1.0)) {
                    cameraPosition = .camera(MapCamera(centerCoordinate: userLocation,
                                                       distance: lastCamera?.distance ?? 3000,
                                                       heading: 0,
                                                       pitch: 0))
                }
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
            }
            withAnimation(.easeInOut(duration: 0.8)) {
                cameraPosition = .userLocation(fallback: .automatic)
            }
            isReturningHome = false
        }
    }
}

#Preview {
    EventMapView()
        .environment(LocationManager())
        .environment(EventStore(events: sampleEvents))
}

