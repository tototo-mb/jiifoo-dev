import SwiftUI
import MapKit

struct CreateEventView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var placeName = ""
    @State private var startsAt = Date().addingTimeInterval(30 * 60)
    @State private var capacity = 3
    @State private var isSaving = false
    @State private var hasCapacityLimit = true

    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var searchResults: [MKMapItem] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    TextField("イベント名", text: $title)
                    TextField("コメント", text: $description, axis: .vertical)
                }

                Section("集合") {
                    // 集合場所の名前。決定キーで検索する
                    TextField("集合場所(例:渋谷駅 ハチ公前)", text: $placeName)
                        .onSubmit { searchPlace() }

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

                    DatePicker("開始時刻", selection: $startsAt,
                               in: Date().addingTimeInterval(6 * 60)...Date().addingTimeInterval(59 * 60),
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

                Section("集合場所(タップで調整できます)") {
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            UserAnnotation()
                            if let pickedCoordinate {
                                Marker("集合場所", coordinate: pickedCoordinate)
                                    .tint(.red)
                            }
                        }
                        .onTapGesture { point in
                            // タップした画面上の位置を、地図の座標に変える
                            if let coordinate = proxy.convert(point, from: .local) {
                                pickedCoordinate = coordinate
                            }
                        }
                    }
                    .frame(height: 220)

                    if isPlaceTooFar {
                        Text("現在地から\(Int(LocationManager.joinableRadius))m以内の場所を選んでください")
                            .font(.footnote)
                            .foregroundStyle(.red)
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
                                  || isPlaceTooFar || pickedCoordinate == nil)
                }
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

        Task {
            isSaving = true
            let success = await eventStore.create(
                title: title,
                category: "other",
                description: description,
                placeName: placeName,
                coordinate: coordinate,
                startsAt: startsAt,
                capacity: hasCapacityLimit ? capacity : nil
            )
            isSaving = false
            if success {
                dismiss()
            }
        }
    }

    // 集合場所の名前で、近くの場所を検索する
    private func searchPlace() {
        guard !placeName.isEmpty, let user = locationManager.userLocation else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = placeName
        request.region = MKCoordinateRegion(center: user,
                                            latitudinalMeters: 3000,
                                            longitudinalMeters: 3000)
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
        }
    }

    // 候補を選んだとき
    private func select(_ item: MKMapItem) {
        let coordinate = item.location.coordinate
        pickedCoordinate = coordinate
        cameraPosition = .region(MKCoordinateRegion(center: coordinate,
                                                    latitudinalMeters: 500,
                                                    longitudinalMeters: 500))
        searchResults = []
    }

    // 選んだ場所が現在地から遠すぎるか
    private var isPlaceTooFar: Bool {
        guard let pickedCoordinate,
              let distance = locationManager.distance(to: pickedCoordinate) else { return false }
        return distance > LocationManager.joinableRadius
    }
}

#Preview {
    CreateEventView()
        .environment(EventStore())
        .environment(LocationManager())
}
