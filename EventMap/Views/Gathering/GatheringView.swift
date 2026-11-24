import SwiftUI
import MapKit
import Supabase

// 集合モードの画面
// ・時間厳守型　-> イベント開催時刻の5分前になったら、参加予定者に通知を送信する
// イベントピンの100m圏内に入ると「到着しました」ボタンを表示
// ・途中参加可能型　-> イベント開催中にイベント開催地100m圏内に入ると自動的に移行
// イベント開催地の制限範囲から離れると自動的に終了、戻れば復活（予定）

struct GatheringView: View {
    let event: GatheringEvent

    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(GatheringMode.self) private var gathering //今集合モード中か
    @AppStorage("showGatheringEffect") private var showGatheringEffect = true   // 集合モードの光を出すか

    @State private var members: [GatheringMember] = []
    @State private var myStatus: String
    @State private var isCheckingIn = false
    @State private var message: String?
    @State private var camera: MapCameraPosition
    @State private var isEnded = false //集合モードが終わったか
    @State private var isCreator = false //自分が主催者か
    @State private var isEnding = false //終了の処理中か
    @State private var showEndConfirm = false //集合モードを終了する前の確認
    @State private var myUserID: UUID?
    @State private var showArrivalChoice = false //「写真を撮る/撮らない」の選択を出すか
    @State private var showCamera = false
    @State private var showCameraNotice = false   // 撮影前の注意(このイベントで初めてのとき)
    @State private var photoUserIDs: Set<UUID> = [] //到着時の写真を撮った人
    @State private var photoReloadID = UUID() //写真を撮り直したら表示を読み直す
    @State private var viewingPhotoMember: GatheringMember? //大きく表示している写真のメンバー
    @State private var photoEvent: PhotoEvent? //終了後に開く撮影画面
    @State private var arrivalStamp: ParticipationStamp? //到着スタンプの演出(出している間だけ入る)


    // サーバーの check_in と同じ値にする
    static let checkInRadius: Double = 100

    init(event: GatheringEvent) {
        self.event = event
        _myStatus = State(initialValue: event.myStatus)
        _camera = State(initialValue: .camera(MapCamera(
            centerCoordinate: event.coordinate, distance: 700, heading: 0, pitch: 45)))
    }

    private var distance: Double? { locationManager.distance(to: event.coordinate) }
    private var isNear: Bool { (distance ?? .infinity) <= Self.checkInRadius }
    private var isCheckedIn: Bool { myStatus == "checked_in" }
    private var arrivedCount: Int { members.filter(\.checkedIn).count }
    private var allArrived: Bool { !members.isEmpty && arrivedCount == members.count }
    // 写真付きで到着できるのは法人イベントだけ(個人イベントは今まで通り)
    private var canArriveWithPhoto: Bool { event.kind == "corporate" }
    //集合モードが終わる時刻（サーバーのends_atと同じ）                 
    private var endsAt: Date { event.endsAt}


    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ---- 地図 ----
                Map(position: $camera) {
                    UserAnnotation()
                    MapCircle(center: event.coordinate, radius: Self.checkInRadius)
                        .foregroundStyle(.orange.opacity(0.15))
                        .stroke(.orange, lineWidth: 1)
                    // 集合場所の目印(柱の根元が集合場所に来るよう anchor を下にする)
                    Annotation(event.placeName, coordinate: event.coordinate, anchor: .bottom) {
                        GatherBeaconView()
                    }
                }
                .frame(height: 300)

                // ---- 情報とメンバー ----
                List {
                    Section {
                        LabeledContent("集合場所", value: event.placeName)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LabeledContent("開始まで", value: countdown(at: context.date))
                        }
                        if let distance {
                            LabeledContent("集合場所まで", value: formatDistance(distance))
                        } else {
                            Text("現在地を取得しています…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("メンバー(\(arrivedCount) / \(members.count)人が到着)") {
                        ForEach(members) { member in
                            HStack {
                                Image(systemName: member.checkedIn ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(member.checkedIn ? .green : .secondary)
                                Text(member.displayName)
                                if member.isCreator {
                                    Text("主催")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.orange, in: Capsule())
                                }
                                Spacer()
                                // 主催者には、到着時に撮った写真を小さく表示(タップで大きく)
                                if isCreator && photoUserIDs.contains(member.userId) {
                                    Button {
                                        viewingPhotoMember = member
                                    } label: {
                                        StoredPhotoView(
                                            path: PhotoStorage.arrivalPath(eventID: event.id, userID: member.userId),
                                            reloadID: photoReloadID)
                                            .frame(width: 36, height: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text(member.checkedIn ? "到着" : "移動中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(event.title)
            // 画面のふちの光を付ける
            .overlay {
                if gathering.isActive && showGatheringEffect {                    
                    ScreenEdgeGlowView(rhythmHaptics: false)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: gathering.isActive)
            // 到着スタンプを押す演出
            .overlay {
                if let arrivalStamp {
                    ArrivalStampOverlay(stamp: arrivalStamp) {
                        self.arrivalStamp = nil
                    }
                }
            }

            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            // 画面下に「到着しました」ボタンを固定
            .safeAreaInset(edge: .bottom) {
                checkInButton
                    .padding()
                    .background(.bar)
            }
            // 画面を開いている間、15秒ごとにメンバーを読み直す(閉じると自動で止まる)
            .task {
                while !Task.isCancelled {
                    await loadMembers()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            //メンバーの参加状況が変わったら、すぐ読み直す
            .task{
                let channel = supabase.channel("gathering-\(event.id)")
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "participations",
                    filter: .eq("event_id",value: event.id)
                )
                try? await channel.subscribeWithError()
                for await _ in changes{
                    await loadMembers()
            }
            //画面を閉じたら止める
            await supabase.removeChannel(channel)
            }
            .sensoryFeedback(.success, trigger: isCheckedIn)
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
            //集合モードが終わる時刻まで待機する
            .task{
                let seconds = endsAt.timeIntervalSinceNow
                if seconds > 0{
                    try? await Task.sleep(for: .seconds(seconds))
                }
                guard !Task.isCancelled else { return }
                isEnded = true
            }
            //自分が主催者か調べる
            .task{
                myUserID = await JiifooAPI.currentUserID()
                isCreator = myUserID == event.creatorId
                if isCreator { await loadMembers() } // 主催者なら写真の一覧もすぐ読み込む
            }
            //到着するとき、写真を撮るか選ぶ(法人イベントのみ)
            .confirmationDialog("到着を記録します",
                                isPresented: $showArrivalChoice,
                                titleVisibility: .visible) {
            Button("写真を撮って到着する") { openCamera() }                
            Button("写真なしで到着する") { checkIn() }
            } message: {
                Text("写真は主催者と参加者だけが見られます")
            }
            // 集合モードを終了する前の確認
            .alert("集合モードを終了しますか？", isPresented: $showEndConfirm) {
                Button("終了する", role: .destructive) { endGathering() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("参加者全員の集合モードも終わります。終了すると元に戻せません。")
            }
            // 撮影前の注意(このイベントで初めてカメラを開くときだけ)
            .alert(PhotoNotice.cameraTitle, isPresented: $showCameraNotice) {
                Button("OK") {
                    PhotoNotice.markCameraNoticeSeen(eventID: event.id)
                    showCamera = true
                }
            } message: {
                Text(PhotoNotice.cameraMessage)
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    arriveWithPhoto(image)
                }
                .ignoresSafeArea()
            }
            //メンバーの到着写真を大きく表示
            .sheet(item: $viewingPhotoMember) { member in
                NavigationStack {
                    StoredPhotoView(
                        path: PhotoStorage.arrivalPath(eventID: event.id, userID: member.userId),
                        reloadID: photoReloadID,
                        contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .navigationTitle(member.displayName)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("閉じる") { viewingPhotoMember = nil }
                            }
                        }
                }
            }
            //
            .task{
                let channel = supabase.channel("gathering-event-\(event.id)")
                let changes = channel.postgresChange(
                    UpdateAction.self,
                    schema: "public",
                    table: "events",
                    filter: .eq("id",value: event.id)
                )
                try? await channel.subscribeWithError()
                for await change in changes{
                    //終了(finished)か中止（cancelled）になったら閉じる
                    let status = change.record["status"]?.stringValue
                    if status == "finished" || status == "cancelled"{
                        isEnded = true
                    }
                }
                await supabase.removeChannel(channel)
            }
            // 到着していた人は、そのまま思い出の写真を撮れる
            .alert("集合モードが終了しました",isPresented: $isEnded){
                if isCheckedIn {
                    Button("写真を撮る") { openMemoryCamera() }
                }
                Button("OK"){ dismiss()}
            } message: {
                if isCheckedIn {
                    Text("会場の中で、撮影終了の時刻まで思い出の写真を撮れます")
                }
            }
            // 撮影画面(閉じたら集合画面も閉じる)
            .sheet(item: $photoEvent, onDismiss: { dismiss() }) { event in
                MemoryCameraView(event: event)
                    .environment(locationManager)
            }

        }
    }

    // カメラを開く(このイベントで初めてなら、先に注意を出す)
    private func openCamera() {
        if PhotoNotice.hasSeenCameraNotice(eventID: event.id) {
            showCamera = true
        } else {
            showCameraNotice = true
        }
    }


    // MARK: - 到着ボタン

    @ViewBuilder
    private var checkInButton: some View {
        VStack(spacing: 8) {
            if !isCheckedIn && !isNear {
                Text("集合場所から\(Int(Self.checkInRadius))m以内に入ると押せます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                // 法人イベントは「写真を撮る/撮らない」を選んでから到着する
                if canArriveWithPhoto {
                    showArrivalChoice = true
                } else {
                    checkIn()
                }
            } label: {
                Label(isCheckedIn ? "到着済み" : "到着しました",
                      systemImage: isCheckedIn ? "checkmark.circle.fill" : "mappin.and.ellipse")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCheckedIn ? .green : .orange)
            .disabled(isCheckedIn || !isNear || isCheckingIn)
            if isCreator {
                Button("集合モードを終了する"){
                    showEndConfirm = true                }
                .disabled(!allArrived || isEnding)
                if !allArrived {
                    Text("制限時間より前に全員の集合が確認できた場合のみ可能")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - 処理

    private func loadMembers() async {
        if let list = try? await JiifooAPI.eventMembers(eventId: event.id) {
            members = list
        }
        // 主催者は、誰が写真を撮ったかも読み込む
        if isCreator && canArriveWithPhoto,
           let ids = try? await PhotoStorage.arrivalPhotoUserIDs(eventID: event.id) {
            photoUserIDs = ids
        }
    }

    // 写真を保存してから到着を記録する
    private func arriveWithPhoto(_ image: UIImage) {
        guard let myUserID else { return }
        isCheckingIn = true
        Task {
            do {
                try await PhotoStorage.upload(
                    image, to: PhotoStorage.arrivalPath(eventID: event.id, userID: myUserID))
                photoReloadID = UUID()
                isCheckingIn = false
                checkIn()   // 写真の保存に成功したら到着を記録
            } catch {
                isCheckingIn = false
                message = "写真を保存できませんでした。もう一度試すか、写真なしで到着してください"
                print("到着写真の保存に失敗:", error)
            }
        }
    }

    private func checkIn() {
        guard let here = locationManager.userLocation else { return }
        isCheckingIn = true
        Task {
            let result = (try? await JiifooAPI.checkIn(
                eventId: event.id, latitude: here.latitude, longitude: here.longitude)) ?? "error"
            isCheckingIn = false

            switch result {
            case "ok", "already_checked_in":
                myStatus = "checked_in"
                await loadMembers()
                // 初めて到着したときだけ、スタンプを押す
                if result == "ok" {
                    let organizer = members.first(where: \.isCreator)?.displayName
                    arrivalStamp = ParticipationStamp(event: event, organizerName: organizer)
                }
            case "too_far":
                message = "集合場所から\(Int(Self.checkInRadius))m以内で押してください"
            case "not_gathering":
                message = "今は集合時間ではありません"
            case "not_member":
                message = "このイベントの参加者ではありません"
            default:
                message = "チェックインできませんでした。通信状況を確認してください"
            }
        }
    }

    // 撮影画面を開く(撮影できるかはサーバーに聞いてから)
    private func openMemoryCamera() {
        Task {
            let list = (try? await JiifooAPI.myPhotoEvents()) ?? []
            if let found = list.first(where: { $0.id == event.id }) {
                photoEvent = found
            } else {
                message = "今は撮影できません。地図の「思い出カメラ」から開いてください"
            }
        }
    }



    private func endGathering() {
        isEnding = true
        Task {
            let result = (try? await JiifooAPI.endEvent(eventId: event.id)) ?? "error"
            isEnding = false
            switch result {
                case "ok","not_gathering":
                    isEnded = true //すでに終了している場合
                case "not_all_arrived":
                    message = "まだ到着していないユーザーがいます"
                    await loadMembers()  //情報を読み直してラグがあるか確認   
                default:
                message = "終了できませんでした。通信状況を確認してください。" 
            }
        }
    }

    // 開始までの残り時間(例:4:32)
    private func countdown(at now: Date) -> String {
        let seconds = Int(event.startsAt.timeIntervalSince(now))
        if seconds <= 0 { return "開始しました" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

extension GatheringEvent {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
