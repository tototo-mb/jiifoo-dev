    import SwiftUI
    import CoreLocation

    // 思い出の写真を撮る画面(1人1イベント最大5枚。撮り直し・削除ができる)
    // 撮影・撮り直しは「会場の中(100m以内)・撮影できる時間内」だけ
struct MemoryCameraView: View {
    let event: PhotoEvent
    
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var locationManager
    
    
    @State private var publicPaths: Set<String> = [] //自分以外のユーザーにも公開している写真
    @State private var paths: [String] = []              // 自分が撮った写真(古い順)
    @State private var reloadIDs: [String: UUID] = [:]   // 撮り直した写真の表示を読み直すため
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var showCamera = false
    @State private var showCameraNotice = false //撮影前の注意喚起(参加したイベントで初めてカメラを起動する時)
    @State private var retakingPath: String?             // 撮り直す写真(nil なら新しく撮る)
    @State private var selectedPath: String?             // 押した写真(撮り直し・削除を選ぶ)
    @State private var deletingPath: String?             // 削除してよいか確認中の写真
    @State private var publishingPath: String?           // 公開してよいか確認中の写真
    @State private var message: String?
    
    // 会場の広さ(サーバーの reserve_photo_slot と同じ)
    static let venueRadius: Double = 100
    
    // あと何枚撮れるか
    private var remaining: Int { max(0, PhotoStorage.maxMemoryPhotos - paths.count) }
    
    // 会場までの距離と、会場の中にいるか
    private var distance: Double? {
        locationManager.distance(to: CLLocationCoordinate2D(latitude: event.latitude,
                                                            longitude: event.longitude))
    }
    private var isInVenue: Bool { (distance ?? .infinity) <= Self.venueRadius }
    
    // 今、撮影・撮り直しができるか(会場の中で、撮影できる時間内)
    private func canShoot(at now: Date) -> Bool {
        isInVenue && now < event.photoUntil
    }
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(paths, id: \.self) { path in
                        Button {
                            selectedPath = path
                        } label: {
                            StoredPhotoView(path: path, reloadID: reloadIDs[path])
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            //公開している写真には地球のマーク表示
                                .overlay(alignment: .topTrailing) {
                                    if publicPaths.contains(path) {
                                        Image(systemName: "globe")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                            .padding(5)
                                            .background(.blue, in: Circle())
                                            .padding(4)
                                    }
                                }
                        }
                                        .buttonStyle(.plain)
                                }
                        }
                        .padding()
                    }
                    .overlay {
                        if isLoading || isSaving {
                            ProgressView()
                        } else if paths.isEmpty {
                            ContentUnavailableView("まだ写真がありません",
                                                   systemImage: "camera",
                                                   description: Text("最大\(PhotoStorage.maxMemoryPhotos)枚まで撮影できます"))
                        }
                    }
                    .navigationTitle(event.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { dismiss() }
                        }
                    }
                    // 画面下に撮影ボタンを固定
                    .safeAreaInset(edge: .bottom) {
                        // 1秒ごとに描き直して、撮影できる時間が過ぎたらボタンを押せなくする
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            VStack(spacing: 8) {
                                shootingStatus(at: context.date)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button {
                                    retakingPath = nil
                                    openCamera()
                                } label: {
                                    Label(remaining > 0 ? "撮影する(あと\(remaining)枚)" : "撮影できる枚数に達しました",
                                          systemImage: "camera.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(remaining == 0 || isSaving || isLoading || !canShoot(at: context.date))
                            }
                            .padding()
                            .background(.bar)
                        }
                    }
                    // 写真を押したら「撮り直す / 削除する」を選ぶ
                    .confirmationDialog("この写真をどうしますか？",
                                        isPresented: Binding(
                                            get: { selectedPath != nil },
                                            set: { if !$0 { selectedPath = nil } }),
                                        titleVisibility: .visible,
                                        presenting: selectedPath) { path in
                        // 撮り直しも、会場の中・時間内だけ
                        if canShoot(at: .now) {
                            Button("撮り直す") {
                                retakingPath = path
                                openCamera()
                            }
                        }
                        if event.joinType == .dropIn {
                            Button(publicPaths.contains(path) ? "公開をやめる" : "みんなに公開") {
                                if publicPaths.contains(path) {
                                    togglePublic(path)       // 公開をやめるときは確認しない
                                } else {
                                    publishingPath = path    // 公開するときは、もう一度確認する
                                }
                            }
                        }
                        
                        Button("削除する", role: .destructive) {
                            deletingPath = path   // すぐには消さず、もう一度確認する
                        }
                    } message: {_ in
                        if event.joinType == .dropIn {
                            Text("公開を選択すると開催中、他のユーザーにも表示されます")
                        }
                    }
                    .fullScreenCover(isPresented: $showCamera) {
                        CameraPicker { image in
                            save(image)
                        }
                        .ignoresSafeArea()
                    }
                    // 公開の確認(ほかの人に見えるようになるため)
                    .alert("この写真を公開しますか？", isPresented: Binding(
                        get: { publishingPath != nil },
                        set: { if !$0 { publishingPath = nil } }
                    ), presenting: publishingPath) { path in
                        Button("公開する") {
                            togglePublic(path)
                        }
                        Button("キャンセル", role: .cancel) { }
                    } message: { _ in
                        Text("開催中は、このイベントを見た人がこの写真を見られるようになります。公開はあとからやめられます。")
                    }
                    // 削除の最終確認(消した写真は元に戻せないため)
                    .alert("この写真を削除しますか？", isPresented: Binding(
                        get: { deletingPath != nil },
                        set: { if !$0 { deletingPath = nil } }
                    ), presenting: deletingPath) { path in
                        Button("削除する", role: .destructive) {
                            delete(path)
                        }
                        Button("キャンセル", role: .cancel) { }
                    } message: { _ in
                        Text("削除した写真は元に戻せません。")
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
                    .alert(message ?? "", isPresented: Binding(
                        get: { message != nil },
                        set: { if !$0 { message = nil } }
                    )) {
                        Button("OK", role: .cancel) { }
                    }
                    .task {
                        await loadPaths()
                    }
                }
            }
            
            // MARK: - 処理

            // カメラを開く(このイベントで初めてなら、先に注意を出す)
            private func openCamera() {
                if PhotoNotice.hasSeenCameraNotice(eventID: event.id) {
                    showCamera = true
                } else {
                    showCameraNotice = true
                }
            }
            
            // このイベントで自分が撮った写真を読み込む
            private func loadPaths() async {
                isLoading = true
                defer { isLoading = false }
                do {
                    paths = try await JiifooAPI.myPhotoPaths(eventId: event.id)
                    publicPaths = try await JiifooAPI.myPublicPhotoPaths(eventId: event.id)
                } catch {
                    message = "写真を読み込めませんでした"
                    print("思い出の写真の読み込みに失敗:", error)
                }
            }
            
            // 撮った写真を保存する(撮り直しなら上書き、そうでなければ1枚増やす)
            private func save(_ image: UIImage) {
                let retaking = retakingPath
                isSaving = true
                Task {
                    do {
                        if let retaking {
                            try await PhotoStorage.retakeMemoryPhoto(image, path: retaking)
                            reloadIDs[retaking] = UUID()   // その写真の表示だけ読み直す
                        } else {
                            guard let here = locationManager.userLocation else {
                                throw PhotoError.tooFar   // 現在地がわからないときは撮れない
                            }
                            let path = try await PhotoStorage.addMemoryPhoto(image, eventID: event.id, here: here)
                            paths.append(path)
                        }
                    } catch {
                        message = error.localizedDescription
                        print("思い出の写真の保存に失敗:", error)
                    }
                    isSaving = false
                }
            }
            
            // 撮影できるかどうかの説明(ボタンの上に出す)
            private func shootingStatus(at now: Date) -> Text {
                if now >= event.photoUntil {
                    return Text("撮影できる時間は終わりました")
                }
                guard let distance else {
                    return Text("現在地を取得しています…")
                }
                if distance > Self.venueRadius {
                    return Text("会場から\(Int(Self.venueRadius))m以内で撮影できます(あと\(formatDistance(distance - Self.venueRadius)))")
                }
                return Text("\(event.photoUntil, format: .dateTime.hour().minute())まで撮影できます")
            }
            
            // みんなに公開するorやめる
            private func togglePublic(_ path: String) {
                let makePublic = !publicPaths.contains(path)
                Task {
                    let result = (try? await JiifooAPI.setPhotoPublic(path: path, isPublic: makePublic)) ?? "error"
                    if result == "ok" {
                        if makePublic {
                            publicPaths.insert(path)
                        } else {
                            publicPaths.remove(path)
                        }
                    } else {
                        message = "公開の設定を変えられませんでした(\(result))"
                    }
                }
            }
            
            
            
            // 写真を消す
            private func delete(_ path: String) {
                isSaving = true
                Task {
                    do {
                        try await PhotoStorage.deleteMemoryPhoto(path: path)
                        paths.removeAll { $0 == path }
                        publicPaths.remove(path)
                    } catch {
                        message = "写真を削除できませんでした"
                        print("写真の削除に失敗:", error)
                    }
                    isSaving = false
                }
            }
        }
            
    
    #Preview {
        MemoryCameraView(event: PhotoEvent(
            id: UUID(), title: "サンプルイベント", placeName: "記念公園",
            latitude: 35.68, longitude: 139.76, joinType: .fixed,
            photoUntil: .now.addingTimeInterval(60 * 60)))
        .environment(LocationManager())
    }
    
    

