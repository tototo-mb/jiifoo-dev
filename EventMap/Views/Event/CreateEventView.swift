import SwiftUI
import MapKit

struct CreateEventView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(AuthManager.self) private var authManager

    // 作成に成功したときに呼ばれる(呼び出し側でマップへ戻す)
    var onCreated: (() -> Void)? = nil
    // 入力途中か(タブを移るときに MainTabView が確かめる)
    @Binding var hasInput: Bool
    // 移ろうとしているタブ(入ると「下書きをどうするか」を聞く)
    @Binding var leaveTo: Int?
    // 聞き終わって、タブを移ってよいときに呼ぶ
    var onLeave: (Int) -> Void = { _ in }

    @State private var title = ""
    @State private var category = ""
    @State private var description = ""
    @State private var placeName = ""
    @State private var startsAt = Date().addingTimeInterval(30 * 60)
    @State private var capacity = 3
    @State private var isSaving = false
    @State private var showCreateConfirm = false   // 作成前の確認
    @State private var showDraftQuestion = false   // 「下書きの続きから書きますか？」
    @State private var hasCapacityLimit = true
    @State private var joinType: JoinType = .fixed //イベントタイプ（合コン型orお祭り型）
    @State private var durationHours = 2 //お祭り型の開催時間の初期値
    @State private var photoEndsAt = Date().addingTimeInterval(90 * 60) //時間厳守型の撮影終了(初期値は開始の1時間後)

 
    // 地図用
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var searchResults: [MKMapItem] = []
    @State private var pickID: UUID?          // 選ぶたびに変わる → 3Dアニメーション開始

    enum PlaceInputMode: String, CaseIterable {
        case map = "マップから選択"
        case search = "検索して選択"
    }
    @State private var inputMode: PlaceInputMode = .map
    @State private var searchText = ""          // 検索用
    @State private var showPlacePicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    TextField("イベント名", text: $title)
                    TextField("コメント", text: $description, axis: .vertical)
                }         

                //法人のイベントタイプの選択が可能（個人で開催する場合は時間厳守タイプのみ）
                if authManager.isCorporate{
                    Section{
                        Picker("タイプ",selection: $joinType){
                            ForEach(JoinType.allCases,id: \.self){type in
                                Text(type.label).tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("イベントタイプ")
                    } footer: {
                        Text(joinTypeDescription)
                    }
                }

                Section("集合") {
                    // 表示用の名前だけ入力する（検索は下の欄で行う）
                    TextField("集合場所（例：渋谷駅　ハチ公前）", text: $placeName)
                    DatePicker("開始時刻", selection: $startsAt,
                               in: startsAtRange,
                               displayedComponents: [.date, .hourAndMinute])
                    switch joinType {
                        case .fixed:
                            Toggle("募集人数に上限を設ける", isOn: $hasCapacityLimit)
                            if hasCapacityLimit {
                                Picker("募集人数", selection: $capacity) {
                                    ForEach(1...10, id: \.self) { n in
                                        Text("\(n)人").tag(n)
                                }
                            }
                        }
                        // 集合したあと、会場内でこの時刻まで思い出の写真を撮れる
                        DatePicker("イベント終了", selection: $photoEndsAt,
                                    in: photoEndsAtRange,
                                    displayedComponents: [.date, .hourAndMinute])
                        // 開始時刻を変えて範囲から外れたら、開始の1時間後に戻す
                        .onChange(of: startsAt) {
                            if !photoEndsAtRange.contains(photoEndsAt) {
                                photoEndsAt = startsAt.addingTimeInterval(60 * 60)
                            }
                        }
                        case .dropIn:
                            Picker("開催時間",selection: $durationHours){
                                ForEach([1,2,3,6,8],id: \.self){ hours in
                                     Text("\(hours)時間").tag(hours)
                                }
                            }
                    }
                }

                Section("集合場所の指定方法") {
                    Picker("指定方法", selection: $inputMode) {
                        ForEach(PlaceInputMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch inputMode {
                    case .map:
                        Button("マップを開いてピンを立てる") { showPlacePicker = true }
                    case .search:
                        TextField("地名・住所を入力", text: $searchText)
                            .onSubmit { searchPlace() }   // 改行キーで検索
                        ForEach(searchResults, id: \.self) { item in
                            Button {
                                select(item)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(item.name ?? "")
                                    Text(item.address?.shortAddress ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // どちらの方法でも、選んだ場所を確認用の地図で表示する
                    if let pickedCoordinate {
                        Map(position: $cameraPosition) {
                            Marker(placeName.isEmpty ? "集合場所" : placeName, coordinate: pickedCoordinate)
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .orbitCamera(on: pickID, coordinate: pickedCoordinate)
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                    }
                }
            }   // ← Form の終わり
            // ↓ ここが「3」の追加場所
            .sheet(isPresented: $showPlacePicker) {
                // 法人はどこでも、個人は現在地から 800m 以内だけ選べる
                PlacePickerMapView(coordinate: $pickedCoordinate,
                                   limitToNearby: !authManager.isCorporate)
            }
            .onChange(of: pickedCoordinate?.latitude) { pickID = UUID() }  // ピンが変わったら3D演出
            // ↑ ここまで
            .navigationTitle("イベントを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("クリア") { resetForm() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { showCreateConfirm = true }
                        .disabled(title.isEmpty || placeName.isEmpty || isSaving)
                }
            }
            // 入力途中かを MainTabView に知らせる
            .onChange(of: formHasInput, initial: true) { _, newValue in
                hasInput = newValue
            }
            // 開いたとき、入力が空で下書きがあれば、続きから書くか聞く
            .onAppear {
                if !formHasInput && EventDraft.load() != nil {
                    showDraftQuestion = true
                }
            }
            .alert("下書きがあります", isPresented: $showDraftQuestion) {
                Button("続きから書く") { restoreDraft() }
                Button("新しく作る", role: .destructive) { EventDraft.delete() }
            } message: {
                Text("前回作成途中だったイベントの続きから書きますか？")
            }
            // 入力途中でほかのタブへ移ろうとしたとき
            .confirmationDialog("作成途中のイベントがあります",
                                isPresented: Binding(
                                    get: { leaveTo != nil },
                                    set: { if !$0 { leaveTo = nil } }),
                                titleVisibility: .visible,
                                presenting: leaveTo) { tab in
                Button("下書きに保存する") {
                    saveDraft()
                    resetForm()
                    leaveTo = nil
                    onLeave(tab)
                }
                Button("削除する", role: .destructive) {
                    EventDraft.delete()
                    resetForm()
                    leaveTo = nil
                    onLeave(tab)
                }
                Button("キャンセル", role: .cancel) { }
            } message: { _ in
                Text("下書きに保存すると、次にこの画面を開いたときに続きから書けます。")
            }
            // 作成前の確認(内容をもう一度見せる)
            .alert("この内容で作成しますか？", isPresented: $showCreateConfirm) {
                Button("作成する") { save() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("""
                \(title)
                \(startsAt.formatted(date: .abbreviated, time: .shortened)) 開始
                集合場所：\(placeName)

                作成したあとは、イベントタイプ・募集人数・開始時刻を変更できません。
                """)
            }
            .alert(eventStore.message ?? "", isPresented: Binding(
                get: { eventStore.message != nil },
                set: { if !$0 { eventStore.message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
        }   // ← NavigationStack の終わり
    }       // ← body の終わり


    // 選べる開始時刻の範囲(Supabase 側のルールより少し内側にしておく)
    //   個人:6分後〜59分後
    //   法人:6分後〜30日後(1時間の余裕をもたせる)
    private var startsAtRange: ClosedRange<Date> {
        let from = Date().addingTimeInterval(6 * 60)
        let to = authManager.isCorporate
            ? Date().addingTimeInterval(30 * 24 * 60 * 60 - 60 * 60)
            : Date().addingTimeInterval(59 * 60)
        return from...to
    }

    // 撮影終了に選べる範囲(開始の1分後〜開始の3時間後。Supabase のルールと同じ)
    private var photoEndsAtRange: ClosedRange<Date> {
        startsAt.addingTimeInterval(60)...startsAt.addingTimeInterval(3 * 60 * 60)
    }



    private var joinTypeDescription: String{
        switch joinType{
            case .fixed:
                return "開始時刻に集合します。人数の上限を決められます。集合モードが開始されると参加を締め切ります。"
            case .dropIn:
                return "指定した開催時間中は自由に参加できます。人数の上限はありません。"
        }
    }



    private func save() {
        // 地図で選んだ場所。選んでいなければ現在地
        guard let coordinate = pickedCoordinate ?? locationManager.userLocation else { return }

        Task {
            isSaving = true
            let success = await eventStore.create(
                title: title,
                category: "other",
                description: description,
                placeName: placeName,
                coordinate: coordinate,
                startsAt: startsAt,
                capacity: (joinType == .fixed && hasCapacityLimit) ? capacity : nil,
                // 法人なら法人IDを送る → Supabase 側で法人イベント(corporate)として扱われる
                // TODO: 複数の法人に所属している場合は、どの法人として作るか選べるようにする
                organizationId: authManager.organizations.first?.id,
                joinType: joinType,
                //途中参加できるイベントだけ終了時刻を送る
                endsAt: joinType == .dropIn
                    ? startsAt.addingTimeInterval(Double(durationHours) * 60 * 60)
                    : nil,
                //時間厳守型だけ撮影終了を送る
                photoEndsAt: joinType == .fixed ? photoEndsAt : nil
            )

            
            isSaving = false
            // 成功したら入力を空に戻して、マップへ戻る(失敗時はアラートが出て画面はそのまま)
            if success {
                EventDraft.delete()   // 作成できたら下書きは捨てる 
                resetForm()
                onCreated?()
            }
        }
    }

        // MARK: - 下書き

    // 何か入力しているか(何もなければ、下書きのことは聞かない)
    private var formHasInput: Bool {
        !title.isEmpty || !description.isEmpty || !placeName.isEmpty || pickedCoordinate != nil
    }

    // 今の入力を下書きに保存する
    private func saveDraft() {
        EventDraft(title: title,
                   description: description,
                   placeName: placeName,
                   startsAt: startsAt,
                   hasCapacityLimit: hasCapacityLimit,
                   capacity: capacity,
                   joinType: joinType,
                   durationHours: durationHours,
                   photoEndsAt: photoEndsAt,
                   latitude: pickedCoordinate?.latitude,
                   longitude: pickedCoordinate?.longitude)
            .save()
    }

    // 下書きを入力欄に戻す
    private func restoreDraft() {
        guard let draft = EventDraft.load() else { return }
        title = draft.title
        description = draft.description
        placeName = draft.placeName
        hasCapacityLimit = draft.hasCapacityLimit
        capacity = draft.capacity
        joinType = draft.joinType
        durationHours = draft.durationHours
        pickedCoordinate = draft.coordinate
        // 開始時刻が、もう選べない時刻になっていたら30分後に戻す
        startsAt = startsAtRange.contains(draft.startsAt)
            ? draft.startsAt
            : Date().addingTimeInterval(30 * 60)
        // 撮影終了も、開始時刻に合わなければ開始の1時間後に戻す
        photoEndsAt = photoEndsAtRange.contains(draft.photoEndsAt)
            ? draft.photoEndsAt
            : startsAt.addingTimeInterval(60 * 60)
    }

    // 入力内容を初期状態に戻す
    private func resetForm() {
        title = ""
        description = ""
        placeName = ""
        startsAt = Date().addingTimeInterval(30 * 60)
        capacity = 3
        hasCapacityLimit = true
        pickedCoordinate = nil
        searchResults = []
        pickID = nil
        searchText = ""
        inputMode = .map
        joinType = .fixed
        durationHours = 2
        photoEndsAt = Date().addingTimeInterval(90 * 60)
    }

    // 集合場所の名前で検索
    private func searchPlace() {
        guard !searchText.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
        }
    }

    // 検索結果を選んだとき
    private func select(_ item: MKMapItem) {
        // 個人は現在地から 800m より遠い場所を選べない
        if !authManager.isCorporate,
           let distance = locationManager.distance(to: item.location.coordinate),
           distance > LocationManager.joinableRadius {
            eventStore.message = "現在地から\(Int(LocationManager.joinableRadius))m以内の場所を選んでください"
            return
        }
        if placeName.isEmpty { placeName = item.name ?? "" }  // 自分で入力した名前を上書きしない
        pickedCoordinate = item.location.coordinate
        searchResults = []
    }

}

#Preview {
    CreateEventView(hasInput: .constant(false), leaveTo: .constant(nil))
        .environment(EventStore())
        .environment(LocationManager())
        .environment(AuthManager())
}