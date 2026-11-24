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
        @AppStorage("showGatheringEffect") private var showGatheringEffect = true   // 集合モードの光と振動を出すか


    // 追従は MapKit 標準の .userLocation を使わず、自分でカメラを動かして行う
    // （.userLocation に切り替えると MapKit が勝手に縮尺を変えるため）
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isFollowing = true                // 現在地を追従中か
    @State private var followDistance: Double = EventMapView.homeDistance // 追従中の高さ(m)
    @State private var hasCenteredOnce = false           // 起動後、最初に現在地へ合わせたか
    @State private var selectedEventID: Event.ID?
    @State private var showCreateEvent = false
    @State private var showFarEvents = false //各地のイベントの一覧を出すか
    @State private var lastCamera: MapCamera?
    @State private var pinScale: CGFloat = 1             // ピンの大きさ(ズームインすると大きくなる)    
    @State private var cameraTask: Task<Void, Never>?   // 実行中のカメラの動き
    @State private var isReturningHome = false          // 現在地へ戻っている最中
    @State private var savedCamera: MapCamera?          // ピンを押す前のカメラ
    @State private var wasFollowing = false             // ピンを押す前に追従中だったか
    @State private var groundScale: Double?             // 真上から見たとき「画面1ポイント÷カメラの高さ」が地面の何mか
    @State private var gatheringStamp: ParticipationStamp? // マップの到着ボタンで到着したときのスタンプ
    @State private var gatheringEvent:GatheringEvent?   //今「集合中」のイベント
    @State private var openedGathering:GatheringEvent?   //開いている集合画面
    @State private var photoEvents: [PhotoEvent] = []    // 今、思い出の写真を撮れるイベント
    @State private var openedPhotoEvent: PhotoEvent?     // 開いている撮影画面
    @State private var showFilter = false               // フィルター画面を表示中か
    @State private var showNearbyList = false           // 近くのイベント一覧を表示中か    
    @State private var openedCluster: EventCluster?     // 一覧を開いている、まとめたピン
    @State private var clusterPickedEvent: Event?       // 一覧で選んだイベント(一覧を閉じたら詳細を開く)

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
        //途中参加型イベントに参加し、初めてイベント開催地に到着した場合
        .overlay {
        if eventStore.arrivalEffectEvent != nil && showGatheringEffect { 
                    ScreenEdgeGlowView()
                    .transition(.opacity)
            }
        }

            .overlay(alignment: .top) {
                arrivalBadge
            }
            // 集合場所の100m以内に入ったら「到着しました」ボタン(まだ到着していないときだけ)
            .overlay(alignment: .bottom) {
                if let event = arrivalTarget {
                    MapArrivalButton(event: event) { isFirst in
                        // 初めて到着したときだけ、スタンプを押す(主催者の名前はメンバー一覧から)
                        if isFirst {
                            let members = (try? await JiifooAPI.eventMembers(eventId: event.id)) ?? []
                            let organizer = members.first(where: \.isCreator)?.displayName
                            gatheringStamp = ParticipationStamp(event: event, organizerName: organizer)
                        }
                        // 到着できたら読み直す(到着済みになるので、ボタンが消える)
                        gatheringEvent = try? await JiifooAPI.myGatheringEvent()
                    }                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring, value: arrivalTarget?.id)
            // 到着スタンプを押す演出(設定に関係なく出す)
            .overlay {
                if let event = eventStore.arrivalStampEvent {
                    ArrivalStampOverlay(stamp: ParticipationStamp(event: event)) {
                        eventStore.arrivalStampEvent = nil
                    }
                }
            }
            // マップの到着ボタンで到着したときのスタンプ
            .overlay {
                if let gatheringStamp {
                    ArrivalStampOverlay(stamp: gatheringStamp) {
                        self.gatheringStamp = nil
                    }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: eventStore.arrivalEffectEvent?.id)
            .task(id: eventStore.arrivalEffectEvent?.id) {
                guard eventStore.arrivalEffectEvent != nil else { return }
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                eventStore.arrivalEffectEvent = nil
        }
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
            get: { eventStore.message != nil && selectedEventID == nil && !showCreateEvent && !showFarEvents && !showFilter && !showNearbyList},
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
            get: { mapEvents.first { $0.id == selectedEventID } },
            set: { if $0 == nil { selectedEventID = nil } }   // 閉じたら選択解除
        )) { event in
            EventDetailView(event: event)
                .environment(eventStore)
                .environment(locationManager)
                .presentationDetents([.medium, .large])
        }
        
        

        // まとめたピンの一覧(選んだら、一覧を閉じてからそのピンへ)
        .sheet(item: $openedCluster, onDismiss: {
            if let event = clusterPickedEvent {
                clusterPickedEvent = nil
                selectPin(event)
            }
        }) { cluster in
            ClusterListView(events: cluster.events) { event in
                clusterPickedEvent = event
                openedCluster = nil
            }
            .presentationDetents([.medium, .large])
        }
        // 近くのイベント一覧(800m圏内)
        .sheet(isPresented: $showNearbyList) {
            NearbyEventListView()
                .environment(eventStore)
                .environment(locationManager)
        }
        // フィルター画面
        .sheet(isPresented: $showFilter) {
            EventFilterView()
                .environment(eventStore)
                .presentationDetents([.medium])
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

        //ユーザーが移動したら参加予定の途中参加可能型イベントの会場に着いたかしらべる
        .onChange(of: arrivingKey) {
            if let here = locationManager.userLocation {
                eventStore.arriveIfNear(here)
            }
        }

        .onChange(of: eventStore.focusedEvent?.id) {
            if let event = eventStore.focusedEvent {
                showFarEvents = false 
                showNearbyList = false //一覧から「マップで場所を見る」を押した時も閉じる
                moveToFocusedEvent(event)
            }
        }
        
        .sheet(isPresented: $showFarEvents) {
            FarEventsView(startCamera: farEventsStartCamera)
            .environment(eventStore)
            .environment(locationManager)
        }

        .task {
            while !Task.isCancelled {
                await checkGathering()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        // 次の集合モードが始まる時刻ぴったりにも確認する(30秒ごとだと最大30秒遅れるため)
        .task(id: eventStore.nextGatheringStart) {
            guard let start = eventStore.nextGatheringStart else { return }
            let wait = start.timeIntervalSinceNow + 1   // サーバーと時計が少しずれても大丈夫なように1秒待つ
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            await checkGathering()
        }

        // 集合中のイベントがあれば、画面の上にバナーを出す
        /*.safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                if let gatheringEvent {
                    gatheringBanner(for: gatheringEvent)
                }
                // 思い出の写真を撮れるイベントがあれば、撮影画面へのバナーも出す
                if let photoEvent = photoEvents.first {
                    photoBanner(for: photoEvent)
                }
            }
        }*/

        // 撮影画面
        .sheet(item: $openedPhotoEvent) { event in
            MemoryCameraView(event: event)
                .environment(locationManager)
        }
        // 集合画面(全画面)
        .fullScreenCover(item: $openedGathering) { event in
            GatheringView(event: event)
                .environment(locationManager)
                .environment(gathering)
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

    // MARK: - 集合モード

    // 自分が集合中のイベントがあるか確認する
    // 始まったら光・振動・カウントダウンを出し、終わったら消す
    private func checkGathering() async {
        let previous = gatheringEvent?.id
        gatheringEvent = try? await JiifooAPI.myGatheringEvent()
        //イベント開催時刻よりも前に会場にいた場合
        if let here = locationManager.userLocation {
            eventStore.arriveIfNear(here)
        }
        // 思い出の写真を撮れるイベント(撮影のバナー用)
        if let list = try? await JiifooAPI.myPhotoEvents() {
            photoEvents = list
        }

        // 集合モードが始まった・終わったとき
        if previous != gatheringEvent?.id {
            if let event = gatheringEvent {
                gathering.start(title: event.title, meetTime: event.startsAt)   // 突入の演出
            } else {
                gathering.stop()
            }
            await eventStore.reload()   // 地図を読み直す(終わったイベントを消すため)
        }
    }



    // MARK: - 画面の部品

    // 会場に初めて着いたときに上に出す「会場に到着しました」(× で演出を消す)
    @ViewBuilder
    private var arrivalBadge: some View {
        if let event = eventStore.arrivalEffectEvent {
            HStack(spacing: 10) {
                Image(systemName: "party.popper.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("会場に到着しました")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(event.title)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                Button {
                    eventStore.arrivalStampEvent = event   // 集合モードを終えたらスタンプを押す
                    eventStore.arrivalEffectEvent = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }



    //イベント一覧表示機能用のカメラ
    private var farEventsStartCamera: MapCamera? {
        guard let here = locationManager.userLocation else { return nil }
        return MapCamera(centerCoordinate: here,
        distance: lastCamera?.distance ?? Self.homeDistance,
        heading: 0,
        pitch: 0)
    }

    //地図に表示するイベント（読み込んだイベントかつ「マップ上で場所を見る」ボタンを押したイベント）
    private var mapEvents: [Event] {
        let shown = eventStore.filteredEvents //絞り込みに合致するイベント
        guard let focused = eventStore.focusedEvent,
            !shown.contains(where: {$0.id == focused.id }) else {
                return shown
        }
        return shown + [focused]
    }    
    
    // 地図を動かせる範囲（現在地から800m）とズームアウトの上限
    private var cameraBounds: MapCameraBounds? {
        // 「地図で場所を見る」で遠くのイベントを見ているときは制限しない
        guard eventStore.focusedEvent == nil,
              let here = locationManager.userLocation else { return nil }
        let region = MKCoordinateRegion(center: here,
                                        latitudinalMeters: Self.limitRadius * 2,
                                        longitudinalMeters: Self.limitRadius * 2)
        return MapCameraBounds(centerCoordinateBounds: region,
                               minimumDistance: nil,
                               maximumDistance: Self.maxZoomOutDistance)
    }

    // 地図
    //地図のボタン
    private var mapLayer: some View {
        MapReader { proxy in
            // 近くのピンをまとめる(ピンが大きいほど、まとめる距離も広く)
            let clusters = EventCluster.make(mapEvents, camera: lastCamera, proxy: proxy, radius: 40 * pinScale)
            Map(position: $cameraPosition, bounds: cameraBounds, selection: $selectedEventID) { 
                UserAnnotation()
                if showJoinableRange, let userLocation = locationManager.userLocation {
                    MapCircle(center: userLocation, radius: LocationManager.joinableRadius)
                        .foregroundStyle(.blue.opacity(0.08))
                        .stroke(.blue.opacity(0.5), lineWidth: 1.5)
                }

                ForEach(clusters) { cluster in
                    if cluster.count == 1 {
                        // 1つだけなら、今までのピン
                        Annotation(cluster.events[0].title, coordinate: cluster.coordinate, anchor: .bottom) {
                            eventPin(for: cluster.events[0])
                        }
                    } else {
                        // 2つ以上なら、件数の丸(タップで一覧)
                        Annotation("\(cluster.count)件", coordinate: cluster.coordinate) {
                            ClusterBubble(cluster: cluster)
                                .onTapGesture { openedCluster = cluster }
                        }
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
                    // 真上から見ているときに、画面と地面の縮尺を測っておく(ピンへのズームで使う)
                    if context.camera.pitch < 1 {
                        measureGroundScale(proxy: proxy, distance: context.camera.distance)
                    }
                                        // 高さに合わせてピンの大きさを変える(動かし終わったときだけ。ふわっと)
                    withAnimation(.easeOut(duration: 0.25)) {
                        pinScale = Self.pinScale(for: context.camera.distance)
                    }
            }
            .ignoresSafeArea()
        }
    }

    // 右下のボタン（フィルター・再読み込み・イベント作成・現在地）
    private var controlButtons: some View {
        VStack(spacing: 12) {
            // 集合モード中だけ:集合モード画面を開く
            if let gatheringEvent {
                colorCircleButton(systemName: "flame.fill", color: .orange) {
                    openedGathering = gatheringEvent
                }
                .accessibilityLabel("集合モード")
            }

            // 思い出の写真を撮れる時間だけ:撮影画面を開く(会場の外では灰色)
            if let photoEvent = photoEvents.first {
                colorCircleButton(systemName: "camera.fill",
                                  color: isInVenue(photoEvent) ? .blue : .gray) {
                    openedPhotoEvent = photoEvent
                }
                                .accessibilityLabel("思い出カメラ")
            }
            // メニュー(絞り込み・再読み込み・全国のイベント)
            menuButton

            // 現在地ボタン
            circleButton(systemName: (isFollowing || isReturningHome) ? "location.fill" : "location") {
                backTo2D()
                eventStore.focusedEvent = nil //「地図で場所を見る」のイベントは消す
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 24)
    }

    // メニューのボタン(押すと、絞り込み・再読み込み・全国のイベントを選べる)
    private var menuButton: some View {
        Menu {
            Button {
                showNearbyList = true
            } label: {
                Label("近くのイベント一覧", systemImage: "list.bullet")
            }
            Button {
                showFarEvents = true
            } label: {
                Label("全国のイベント", systemImage: "globe.asia.australia")
            }
            Divider()
            Button {
                showFilter = true
            } label: {
                Label(eventStore.filter.isActive ? "絞り込み(使用中)" : "絞り込み",
                      systemImage: "line.3.horizontal.decrease")
            }
            Button {
                if let userLocation = locationManager.userLocation {
                    Task { await eventStore.load(near: userLocation, force: true) }
                }
            } label: {
                Label("再読み込み", systemImage: "arrow.clockwise")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 50, height: 50)
                .background(.regularMaterial, in: Circle())
                // 絞り込み中は、右上にオレンジの点
                .overlay(alignment: .topTrailing) {
                    if eventStore.filter.isActive {
                        Circle()
                            .fill(.orange)
                            .frame(width: 12, height: 12)
                            .offset(x: -2, y: 2)
                    }
                }
                .shadow(radius: 3)
        }
        .accessibilityLabel("メニュー")
    }

    // 色付きの丸いボタン(集合モード・カメラなど、その時間だけ出すもの)
    private func colorCircleButton(systemName: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(color, in: Circle())
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(radius: 3)
        }
    }

    // 撮影の会場の中にいるか(カメラのボタンの色に使う)
    private func isInVenue(_ event: PhotoEvent) -> Bool {
        let distance = locationManager.distance(
            to: CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude))
        return (distance ?? .infinity) <= MemoryCameraView.venueRadius
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

    //会場に着いたかを調べる用,10mごとに変化
    private var arrivingKey: String{
        guard let l = locationManager.userLocation else { return "none" }
        return String(format: "%.4f,%.4f", l.latitude, l.longitude)
    }

    // 現在地をおよそ100m単位に丸めた目印。これが変わったら読み込み直す
    private var locationKey: String {
        guard let l = locationManager.userLocation else { return "none" }
        return String(format: "%.3f,%.3f", l.latitude, l.longitude)
    }
    // 撮影画面を開くバナー(会場の外では灰色。開いて写真を見ることはできる)
    private func photoBanner(for event: PhotoEvent) -> some View {
        let distance = locationManager.distance(
            to: CLLocationCoordinate2D(latitude: event.latitude, longitude: event.longitude))
        let isInVenue = (distance ?? .infinity) <= MemoryCameraView.venueRadius
        return Button {
            openedPhotoEvent = event
        } label: {
            HStack {
                Image(systemName: "camera.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text(isInVenue ? "思い出カメラ" : "会場から離れています")
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
            .background(isInVenue ? Color.blue : Color.gray, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }

    // 「到着しました」ボタンを出す、集合中のイベント
    // (集合場所の100m以内にいて、まだ到着していないときだけ。それ以外は nil)
    private var arrivalTarget: GatheringEvent? {
        guard let event = gatheringEvent,
              event.myStatus != "checked_in",
              let distance = locationManager.distance(to: event.coordinate),
              distance <= GatheringView.checkInRadius else { return nil }
        return event
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
        // 開始時刻を過ぎたら「開催中」の目印を付ける(10秒ごとに確かめる)
        TimelineView(.periodic(from: .now, by: 10)) { context in
            let isLive = event.startsAt <= context.date
            Group {
                if isLive {
                    // 開催中:fire_pin.riv の炎(タップは炎の根元だけ)
                    FirePinView(style: .live) {
                        selectPin(event)
                    }
                    .saturation(joinable ? 1 : 0)
                    .opacity(joinable ? 1 : 0.6)
                } else {
                    // 開始前:今までの炎
                    Group {
                        if event.scale == .businessMode {
                            BusinessPinView(isJoinable: joinable)
                        } else {
                            PrivatePinView(isJoinable: joinable)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectPin(event)
                    }
                }
            }
            .livePinEffect(isLive)
            .scaleEffect(pinScale, anchor: .bottom)   // ズームインしたら大きく
        }
    }

    // ピンを押したとき:詳細を開いて、そのピンへズームする
    private func selectPin(_ event: Event) {
        // ピンを押す前のカメラを記録（2回目以降のタップでは上書きしない）
        if savedCamera == nil {
            savedCamera = lastCamera
            wasFollowing = isFollowing
        }

        isFollowing = false   // ピンを見ている間は現在地に引き戻さない
        selectedEventID = event.id
        zoomToEvent(event)
    }

    // カメラの高さに合わせたピンの大きさ(近づくほど大きく。最大2倍)
    // 平方根(sqrt)を使って、近づいたときに急に大きくなりすぎないようにする
    private static func pinScale(for distance: Double) -> CGFloat {
        let scale = (homeDistance / max(distance, 1)).squareRoot()
        return CGFloat(min(max(scale, 1), 2))
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

    // 地図で見える範囲の半径(m)。イベントの表示範囲(800m)より少し広めにする
    private static let limitRadius: CLLocationDistance = 1000
    // いちばん引いたときのカメラの高さ(m)。半径に合わせて自動で計算する
    // (800mのとき3000mだった比率をそのまま使う)
    private static let maxZoomOutDistance: Double = limitRadius * 3.75
    private static let homeDistance: Double = maxZoomOutDistance   // 現在地ボタンで戻るときの高さ(m)    // ピンを選んだとき：真上から見たまま、ピンへズームする（傾けたり回したりはしない）
    private func zoomToEvent(_ event: Event) {
        cameraTask?.cancel()   // 前の動きを止める
        isReturningHome = false
        let heading = lastCamera?.heading ?? 0   // 今の向きのまま
        withAnimation(.easeInOut(duration: 1.5)) {
            cameraPosition = .camera(zoomCamera(around: event.coordinate, heading: heading))
        }
    }

    // ピンを上から1/4に置くための、中心のずらし量(m)
    // 画面の真ん中から上1/4の位置までのポイント数 × 1ポイントあたりの地面の長さ
    // (まだ測れていないときは仮の値 200m)
    private var currentOffset: Double {
        guard let groundScale else { return 200 }
        let points = Double(UIScreen.main.bounds.height * (0.5 - pinScreenRatio))
        return points * groundScale * zoomDistance
    }

    // 画面の真ん中と、その100ポイント下が、地面で何m離れているかを測る
    // カメラの高さで割っておけば、どの高さでも使える(真上から見たとき、地面の縮尺は高さに比例する)
    private func measureGroundScale(proxy: MapProxy, distance: Double) {
        let screen = UIScreen.main.bounds
        let center = CGPoint(x: screen.midX, y: screen.midY)
        let below = CGPoint(x: screen.midX, y: screen.midY + 100)
        guard distance > 0,
              let a = proxy.convert(center, from: .global),
              let b = proxy.convert(below, from: .global) else { return }
        let meters = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        groundScale = meters / 100 / distance
    }

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

    //「地図で場所を見る」ボタンを押したイベントの場所へ移動する
    private func moveToFocusedEvent(_ event: Event) {
        cameraTask?.cancel()
        savedCamera = nil
        isFollowing = false
        isReturningHome = false
        withAnimation(.easeInOut(duration: 1.5)) {
            cameraPosition = .camera(MapCamera(centerCoordinate: event.coordinate,
                                                distance: 1500,
                                                heading: 0,
                                                pitch: 0))
        }
    }

    // 現在地ボタン：2D（真上・北が上）に戻して現在地追従へ
    private func backTo2D() {
        cameraTask?.cancel()
        savedCamera = nil      // 詳細を閉じたときの「元に戻る」は使わない
        selectedEventID = nil
        followDistance = Self.homeDistance   // 毎回同じ縮尺で追従する

        if let userLocation = locationManager.userLocation {
            cameraPosition = .camera(MapCamera(centerCoordinate: userLocation,
                                                distance: Self.homeDistance,
                                                heading: 0,
                                                pitch: 0))
        } 
        // ここで .userLocation に切り替えない（切り替えると縮尺が勝手に戻ってしまう）
        isReturningHome = false
        isFollowing = true
        hasCenteredOnce = true
    }
}


#Preview {
    EventMapView()
        .environment(LocationManager())
        .environment(EventStore(events: sampleEvents))
        .environment(GatheringMode())
        .environment(AuthManager())
}
        

