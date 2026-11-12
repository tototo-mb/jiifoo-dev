import SwiftUI
import MapKit

// ① 地図でイベントを見る画面（旧 CurrentlocationMapView）
struct EventMapView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore
    @Environment(GatheringMode.self) private var gathering   // 集合モード（GroupModeUI.swift）
    @Environment(AuthManager.self) private var authManager
    // 設定画面の「参加できる範囲を表示」と同じ名前で読む
    @AppStorage("showJoinableRange") private var showJoinableRange = true


    // 追従は MapKit 標準の .userLocation を使わず、自分でカメラを動かして行う
    // （.userLocation に切り替えると MapKit が勝手に縮尺を変えるため）
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isFollowing = true                // 現在地を追従中か
    @State private var followDistance: Double = EventMapView.homeDistance // 追従中の高さ(m)
    @State private var hasCenteredOnce = false           // 起動後、最初に現在地へ合わせたか
    @State private var selectedEventID: Event.ID?
    @State private var showCreateEvent = false
    @State private var lastCamera: MapCamera?
    @State private var cameraTask: Task<Void, Never>?   // 実行中のカメラの動き
    @State private var isReturningHome = false          // 現在地へ戻っている最中
    @State private var savedCamera: MapCamera?          // ピンを押す前のカメラ
    @State private var wasFollowing = false             // ピンを押す前に追従中だったか
    @State private var mapProxy: MapProxy?              // 画面の位置 ⇔ 地図の座標の変換用
    @State private var measuredOffset: Double?          // 実際の画面で測ったずらし量(m)
    @State private var gatheringEvent:GatheringEvent?   //今「集合中」のイベント
    @State private var openedGathering:GatheringEvent?   //開いている集合画面

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mapLayer

            // 読み込み中の表示(上部中央)。集合モード中はカウントダウンの下にずらす
            if eventStore.isLoading {
                ProgressView()
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    .padding(.top, (gathering.isActive || gatheringEvent != nil) ? 80 : 8)

            }

            controlButtons
        }
        // 集合モードの光とカウントダウン（GroupModeUI.swift）
        .gatheringModeOverlay()
        // ▼ テスト用：起動したら10分後集合で集合モードを始める（集合機能ができたら消す）
        /*.onAppear {
            if !gathering.isActive { gathering.start(title: "集合", minutes: 10) }
        }*/
        // およそ100m動くたびに読み込みを試す(実際の読み込みは300m以上動いたときだけ)
        .task(id: locationKey) {
            if let userLocation = locationManager.userLocation {
                await eventStore.load(near: userLocation)
            }
        }
        // 起動時、すでに現在地がわかっていればそこへ合わせる
        .onAppear { followUser() }
        // 現在地が動いたら、追従中ならカメラもついていく
        .onChange(of: followKey) { _, _ in
            followUser()
        }
        // ユーザーが地図を指で動かしたら追従をやめる
        .onChange(of: cameraPosition) { _, newValue in
            if newValue.positionedByUser {
                isFollowing = false
                if isReturningHome {          // 戻る途中で触られたら戻るのも中止
                    cameraTask?.cancel()
                    isReturningHome = false
                }
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
            // 許可されたら改めて現在地の追従を始める（位置が届いた時点でカメラが動く）
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                isFollowing = true
                followUser()
            default:
                break
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
        /*
        .sheet(isPresented: $showCreateEvent) {
            // 作成に成功したらシートを閉じてマップに戻る
            CreateEventView(onCreated: { showCreateEvent = false })
                .environment(eventStore)
                .environment(locationManager)
                .environment(authManager)
        }
        */

        // 30秒ごとに「自分が集合中のイベントがあるか」を確認する
        .task {
            while !Task.isCancelled {
                let previous = gatheringEvent?.id
                gatheringEvent = try? await JiifooAPI.myGatheringEvent()
                // 集合モードが始まった・終わったら地図を読み直す(終わったイベントを消すため)
                if previous != gatheringEvent?.id {
                    await eventStore.reload()
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // 集合中のイベントがあれば、画面の上にバナーを出す
        .safeAreaInset(edge: .top) {
            if let gatheringEvent {
                gatheringBanner(for: gatheringEvent)
            }
        }
        // 集合画面(全画面)
        .fullScreenCover(item: $openedGathering) { event in
            GatheringView(event: event)
                .environment(locationManager)
        }
        //通知がタップされたら、集合画面を開く
        .onChange(of: NotificationDelegate.shared.tappedEventID){_,eventID in
            guard let eventID else {return}
            Task{
                gatheringEvent = try? await JiifooAPI.myGatheringEvent()
                if let gatheringEvent, gatheringEvent.id == eventID{
                    openedGathering = gatheringEvent
                }
            NotificationDelegate.shared.tappedEventID = nil //開いたら連絡板を消す    
        }
    }
}

    // MARK: - 画面の部品

    // 地図
    //地図のボタン
    private var mapLayer: some View {
        MapReader { proxy in
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
                    lastCamera = context.camera   // カメラの位置だけ記録する(読み込みの基準は現在地)
            }
            .ignoresSafeArea()
            .onAppear { mapProxy = proxy }
        }
    }

    // 右下のボタン（再読み込み・イベント作成・現在地）
    private var controlButtons: some View {
        VStack(spacing: 12) {
            // 再読み込みボタン
            circleButton(systemName: "arrow.clockwise") {
                if let userLocation = locationManager.userLocation {
                    Task { await eventStore.load(near: userLocation, force: true) }
                }
            }

            // イベント作成ボタン
            /*
            circleButton(systemName: "plus") {
                showCreateEvent = true
            }
            .disabled(locationManager.userLocation == nil)   // 現在地がわかるまで押せない
            */
            
            // 現在地ボタン
            circleButton(systemName: (isFollowing || isReturningHome) ? "location.fill" : "location") {
                backTo2D()
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 24)
    }

    // 丸いボタン1つ分の見た目
    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 50, height: 50)
                .background(.regularMaterial, in: Circle())
                .shadow(radius: 3)
        }
    }

    // 現在地をおよそ100m単位に丸めた目印。これが変わったら読み込み直す
    private var locationKey: String {
        guard let l = locationManager.userLocation else { return "none" }
        return String(format: "%.3f,%.3f", l.latitude, l.longitude)
    }
    // 集合モードのバナー(body が長くなりすぎないよう分けている)
    private func gatheringBanner(for event: GatheringEvent) -> some View {
        Button {
            openedGathering = event
        } label: {
            HStack {
                Image(systemName: "flame.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("集合モード")
                        .font(.caption.bold())
                    Text(event.title)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Spacer()
                Text("開く")
                    .font(.subheadline.bold())
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.orange, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }
    
    // 追従用の目印（およそ1m単位）。これが変わったらカメラを動かす
    private var followKey: String {
        guard let l = locationManager.userLocation else { return "none" }
        return String(format: "%.5f,%.5f", l.latitude, l.longitude)
    }
    
    // ピン1つ分の見た目
    // 法人ならBusinessPin、個人ユーザーならPrivatePinを立てる
    @ViewBuilder
    private func eventPin(for event: Event) -> some View {
        let joinable = locationManager.isJoinable(event.coordinate)
        Group {
            if event.scale == .businessMode {
                BusinessPinView(isJoinable: joinable)
            } else {
                PrivatePinView(isJoinable: joinable)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // ピンを押す前のカメラを記録（2回目以降のタップでは上書きしない）
            if savedCamera == nil {
                savedCamera = lastCamera
                wasFollowing = isFollowing
            }

            isFollowing = false   // ピンを見ている間は現在地に引き戻さない
            selectedEventID = event.id
            zoomToEvent(event)
        }
    }

    // MARK: - 現在地の追従

    // 追従中なら、今の高さ(followDistance)のまま現在地を真上から映す
    private func followUser() {
        guard isFollowing, !isReturningHome,
              let userLocation = locationManager.userLocation else { return }
        let camera = MapCamera(centerCoordinate: userLocation,
                               distance: followDistance,
                               heading: 0,
                               pitch: 0)
        if hasCenteredOnce {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .camera(camera)
            }
        } else {
            cameraPosition = .camera(camera)   // 起動直後はアニメーションなしで合わせる
            hasCenteredOnce = true
        }
    }

    // MARK: - カメラ

    private let zoomDistance: Double = 800      // 近づく距離(m)
    private let pinScreenRatio: CGFloat = 0.25  // ピンを置きたい位置（上から1/4。下の詳細シートに隠れないように）
    private static let homeDistance: Double = 5000   // 現在地ボタンで戻るときの高さ(m)。小さいほど拡大

    // ピンを選んだとき：真上から見たまま、ピンへズームする（傾けたり回したりはしない）
    private func zoomToEvent(_ event: Event) {
        cameraTask?.cancel()   // 前の動きを止める
        isReturningHome = false
        let heading = lastCamera?.heading ?? 0   // 今の向きのまま
        
        cameraTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 1.5)) {
                cameraPosition = .camera(zoomCamera(around: event.coordinate, heading: heading))
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            // 初回だけ：実際の画面で位置を測って、ピンが上から1/4に来るよう微調整
            if measuredOffset == nil, let proxy = mapProxy {
                let screen = UIScreen.main.bounds.size
                let target = CGPoint(x: screen.width / 2, y: screen.height * pinScreenRatio)
                if let ground = proxy.convert(target, from: .global) {
                    let forward = forwardMeters(from: event.coordinate, to: ground, heading: heading)
                    measuredOffset = currentOffset + forward
                    withAnimation(.easeInOut(duration: 0.6)) {
                        cameraPosition = .camera(zoomCamera(around: event.coordinate, heading: heading))
                    }
                }
            }
        }
    }

    // 今のずらし量（測る前は仮の値）
    private var currentOffset: Double { measuredOffset ?? 200 }

    // ピンが画面の上側に見えるカメラを作る（向いている方向の手前へ中心をずらす）
    private func zoomCamera(around coordinate: CLLocationCoordinate2D, heading: Double) -> MapCamera {
        let rad = (heading + 180) * .pi / 180
        let dLat = currentOffset * cos(rad) / 111_000
        let dLon = currentOffset * sin(rad) / (111_000 * cos(coordinate.latitude * .pi / 180))
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude + dLat,
                                            longitude: coordinate.longitude + dLon)
        return MapCamera(centerCoordinate: center,
                         distance: zoomDistance,
                         heading: heading,
                         pitch: 0)   // 0 = 真上から見る(2D)
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

        cameraTask?.cancel()
        if follow { isReturningHome = true }

        cameraTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 1.5)) {
                cameraPosition = .camera(saved)
            }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }

            isReturningHome = false
            // 追従中だった場合は、戻った高さのまま追従を再開する（縮尺は変えない）
            if follow {
                followDistance = saved.distance
                isFollowing = true
                followUser()
            }
        }
    }

    // 現在地ボタン：2D（真上・北が上）に戻して現在地追従へ
    private func backTo2D() {
        cameraTask?.cancel()
        savedCamera = nil      // 詳細を閉じたときの「元に戻る」は使わない
        selectedEventID = nil
        isReturningHome = true // 押した瞬間にアイコンを青く
        followDistance = Self.homeDistance   // 毎回同じ縮尺で追従する

        cameraTask = Task { @MainActor in
            if let userLocation = locationManager.userLocation {
                withAnimation(.easeInOut(duration: 1.0)) {
                    cameraPosition = .camera(MapCamera(centerCoordinate: userLocation,
                                                       distance: Self.homeDistance,
                                                       heading: 0,
                                                       pitch: 0))
                }
                try? await Task.sleep(for: .seconds(1.0))
                guard !Task.isCancelled else { return }
            }
            // ここで .userLocation に切り替えない（切り替えると縮尺が勝手に戻ってしまう）
            isReturningHome = false
            isFollowing = true
            hasCenteredOnce = true
        }
    }
}

#Preview {
    EventMapView()
        .environment(LocationManager())
        .environment(EventStore(events: sampleEvents))
        .environment(GatheringMode())
        .environment(AuthManager())
}
        

