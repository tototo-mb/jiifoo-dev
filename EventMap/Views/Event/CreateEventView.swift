import SwiftUI
import MapKit

// ピンの位置の決め方
enum PlaceMode: String, CaseIterable, Identifiable {
    case search = "住所・地名で指定"
    case map = "マップから選択"
    var id: Self { self }
}

struct CreateEventView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var placeName = ""            // 集合場所の名前(表示用。例:松本駅 お城口 改札前)
    @State private var startsAt = Date().addingTimeInterval(30 * 60)
    @State private var capacity = 3
    @State private var isSaving = false
    @State private var hasCapacityLimit = true

    // ピンの位置
    @State private var placeMode: PlaceMode = .search
    @State private var searchQuery = ""          // 住所・地名の検索に使う文字
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var showMapPicker = false

    // 誰として作るか(法人に所属している人だけ選べる)
    @State private var organizations: [Organization] = []   // 投稿できる法人
    @State private var postAs: Organization?                // nil なら個人として作る

    private var isCorporate: Bool { postAs != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    // 法人に所属している人だけ「作成者」を選べる
                    if !organizations.isEmpty {
                        Picker("作成者", selection: $postAs) {
                            Text("個人として").tag(Organization?.none)
                            ForEach(organizations) { org in
                                Text(org.name).tag(Organization?.some(org))
                            }
                        }
                    }
                    TextField("イベント名", text: $title)
                    TextField("コメント", text: $description, axis: .vertical)
                }

                Section("集合場所") {
                    TextField("集合場所の名前(例:松本駅 お城口 改札前)", text: $placeName)
                }

                Section("ピンの位置") {
                    Picker("指定方法", selection: $placeMode) {
                        ForEach(PlaceMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch placeMode {
                    case .search:
                        // 住所・地名で検索
                        HStack {
                            TextField(isCorporate ? "住所や地名(例:長野県松本市丸の内4-1)" : "住所や地名(例:松本駅)",
                                      text: $searchQuery)
                                .onSubmit { searchPlace() }
                            Button("検索") { searchPlace() }
                                .disabled(searchQuery.isEmpty || isSearching)
                        }

                        // 検索結果の候補
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                select(item)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "名前なし")
                                    if let distance = locationManager.distance(to: item.location.coordinate) {
                                        Text("現在地から \(formatDistance(distance))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                    case .map:
                        // 全画面の地図を開いて選ぶ
                        Button {
                            showMapPicker = true
                        } label: {
                            Label("マップ上から選択", systemImage: "map")
                        }
                    }

                    // 選んだ場所の確認
                    if let pickedCoordinate {
                        Map(position: .constant(.region(MKCoordinateRegion(
                            center: pickedCoordinate, latitudinalMeters: 400, longitudinalMeters: 400))),
                            interactionModes: []) {
                            Marker("集合場所", coordinate: pickedCoordinate)
                                .tint(.red)
                        }
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        if let distance = locationManager.distance(to: pickedCoordinate) {
                            Text("現在地から \(formatDistance(distance))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if isPlaceTooFar {
                        Text("現在地から\(Int(LocationManager.joinableRadius))m以内の場所を選んでください")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section("日時と人数") {
                    DatePicker("開始時刻", selection: $startsAt,
                               in: Date().addingTimeInterval(6 * 60)...latestStart,
                               displayedComponents: [.date, .hourAndMinute])

                    Toggle("募集人数に上限を設ける", isOn: $hasCapacityLimit)
                    if hasCapacityLimit {
                        Picker("募集人数", selection: $capacity) {
                            ForEach(1...10, id: \.self) { n in
                                Text("\(n)人").tag(n)
                            }
                        }
                    }
                }
            }
            .navigationTitle("イベントを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { save() }
                        .disabled(title.isEmpty || placeName.isEmpty || isSaving
                                  || pickedCoordinate == nil || isPlaceTooFar)
                }
            }
            // 開いたときに、投稿できる法人の一覧を読み込む
            .task {
                organizations = (try? await JiifooAPI.myPostableOrganizations()) ?? []
            }
            // 「マップ上から選択」で開く全画面の地図
            .fullScreenCover(isPresented: $showMapPicker) {
                PlacePickerMapView(coordinate: $pickedCoordinate, limitToNearby: !isCorporate)
                    .environment(locationManager)
            }
            .alert(eventStore.message ?? "", isPresented: Binding(
                get: { eventStore.message != nil },
                set: { if !$0 { eventStore.message = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    // MARK: - 処理

    private func save() {
        guard let coordinate = pickedCoordinate else { return }

        // 開始時刻が範囲外なら理由を伝えて止める(画面を開いたまま時間が経った場合など)
        guard startsAt >= Date().addingTimeInterval(5 * 60), startsAt <= latestStart else {
            eventStore.message = isCorporate
                ? "開始時刻は今から5分後〜30日後の間で選んでください"
                : "開始時刻は今から5分後〜1時間後の間で選んでください"
            return
        }

        Task {
            isSaving = true
            let success = await eventStore.create(
                title: title,
                category: "other",
                description: description,
                placeName: placeName,
                coordinate: coordinate,
                startsAt: startsAt,
                capacity: hasCapacityLimit ? capacity : nil,
                organizationId: postAs?.id        // 法人として作るときだけ法人IDを送る
            )
            isSaving = false
            if success {
                dismiss()
            }
        }
    }

    // 住所・地名で検索する
    // 個人:現在地の近く(3km)を優先 / 法人:広い範囲(100km)を優先
    private func searchPlace() {
        guard !searchQuery.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        if let user = locationManager.userLocation {
            let meters: CLLocationDistance = isCorporate ? 100_000 : 3000
            request.region = MKCoordinateRegion(center: user,
                                                latitudinalMeters: meters,
                                                longitudinalMeters: meters)
        }
        isSearching = true
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
            isSearching = false
            if searchResults.isEmpty {
                eventStore.message = "「\(searchQuery)」は見つかりませんでした"
            }
        }
    }

    // 検索結果の候補を選んだとき
    private func select(_ item: MKMapItem) {
        pickedCoordinate = item.location.coordinate
        // 集合場所の名前が空なら、選んだ場所の名前を入れておく
        if placeName.isEmpty, let name = item.name {
            placeName = name
        }
        searchResults = []
    }

    // 開始時刻の上限:個人は1時間後まで、法人は30日後まで
    private var latestStart: Date {
        Date().addingTimeInterval(isCorporate ? 30 * 24 * 60 * 60 : 59 * 60)
    }

    // 選んだ場所が現在地から遠すぎるか(法人は距離の制限なし)
    private var isPlaceTooFar: Bool {
        guard !isCorporate, let pickedCoordinate,
              let distance = locationManager.distance(to: pickedCoordinate) else { return false }
        return distance > LocationManager.joinableRadius
    }
}

#Preview {
    CreateEventView()
        .environment(EventStore())
        .environment(LocationManager())
}
