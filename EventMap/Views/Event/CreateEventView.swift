import SwiftUI
import MapKit

struct CreateEventView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category = ""
    @State private var description = ""
    @State private var placeName = ""
    @State private var startsAt = Date().addingTimeInterval(30 * 60)
    @State private var capacity = 3
    @State private var isSaving = false
    @State private var hasCapacityLimit = true

    // 地図用
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var searchResults: [MKMapItem] = []
    @State private var pickID: UUID?          // 選ぶたびに変わる → 3Dアニメーション開始

    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    TextField("イベント名", text: $title)
                    TextField("コメント", text: $description, axis: .vertical)
                }

                Section("集合") {
                    TextField("集合場所（例：渋谷駅　ハチ公前）", text: $placeName)
                        .onSubmit { searchPlace() }   // 改行キーで検索

                    // 検索結果
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

                Section("集合場所を地図で選ぶ（タップで指定）") {
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            UserAnnotation()
                            if let pickedCoordinate {
                                Marker(placeName.isEmpty ? "集合場所" : placeName,
                                       coordinate: pickedCoordinate)
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))          // 3D表示
                        .orbitCamera(on: pickID, coordinate: pickedCoordinate) // Componentsのファイル
                        .onTapGesture { point in
                            if let coord = proxy.convert(point, from: .local) {
                                pickedCoordinate = coord
                                pickID = UUID()
                            }
                        }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
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
                        .disabled(title.isEmpty || placeName.isEmpty || isSaving)
                }
            }
            .alert(eventStore.message ?? "", isPresented: Binding(
                get: { eventStore.message != nil },
                set: { if !$0 { eventStore.message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
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
                capacity: hasCapacityLimit ? capacity : nil
            )
            isSaving = false
            if success { dismiss() }
        }
    }

    // 集合場所の名前で検索
    private func searchPlace() {
        guard !placeName.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = placeName
        Task {
            let response = try? await MKLocalSearch(request: request).start()
            searchResults = response?.mapItems ?? []
        }
    }

    // 検索結果を選んだとき
    private func select(_ item: MKMapItem) {
        placeName = item.name ?? placeName
        pickedCoordinate = item.location.coordinate
        searchResults = []
        pickID = UUID()
    }
}

#Preview {
    CreateEventView()
        .environment(EventStore())
        .environment(LocationManager())
}
