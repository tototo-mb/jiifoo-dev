import SwiftUI
import MapKit

// イベント編集画面(主催者用。詳細画面の「イベントを編集する」から開く)
// 変えられるのは イベント名・コメント・集合場所 だけ
// イベントタイプ・募集人数・開始時刻は表示のみ(変えられない)
struct EditEventView: View {
    let event: Event
    @Environment(EventStore.self) private var eventStore
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var description: String
    @State private var placeName: String
    @State private var pickedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition
    @State private var showPlacePicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(event: Event) {
        self.event = event
        _title = State(initialValue: event.title)
        _description = State(initialValue: event.description)
        _placeName = State(initialValue: event.placeName)
        _pickedCoordinate = State(initialValue: event.coordinate)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: event.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    TextField("イベント名", text: $title)
                    TextField("コメント", text: $description, axis: .vertical)
                }

                Section {
                    TextField("集合場所（例：渋谷駅　ハチ公前）", text: $placeName)
                    Button("マップを開いて場所を変える") { showPlacePicker = true }

                    if let pickedCoordinate {
                        Map(position: $cameraPosition) {
                            Marker(placeName.isEmpty ? "集合場所" : placeName, coordinate: pickedCoordinate)
                        }
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("集合場所")
                } footer: {
                    if isPlaceChanged {
                        Text("集合場所を変えると、参加者が次にアプリを開いたときにお知らせが表示されます。")
                    }
                }

                // 変えられない項目(確認用に表示だけ)
                Section {
                    LabeledContent("タイプ", value: event.joinType.label)
                    LabeledContent("募集人数",
                                   value: event.capacity.map { "\($0)人" } ?? "上限なし")
                    LabeledContent("開始") {
                        Text(event.startsAt, format: .dateTime.month().day().hour().minute())
                    }
                } header: {
                    Text("変更できない項目")
                } footer: {
                    Text("イベントタイプ・募集人数・開始時刻は変更できません。集合モードが始まると編集できなくなります。")
                }
            }
            .navigationTitle("イベントを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showPlacePicker) {
                // 法人はどこでも、個人は現在地から 800m 以内だけ選べる(作成画面と同じ)
                PlacePickerMapView(coordinate: $pickedCoordinate,
                                   limitToNearby: !authManager.isCorporate)
            }
            .onChange(of: pickedCoordinate?.latitude) {
                if let pickedCoordinate {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: pickedCoordinate, latitudinalMeters: 500, longitudinalMeters: 500))
                }
            }
            .alert(errorMessage ?? "", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - 入力チェック

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedPlace: String { placeName.trimmingCharacters(in: .whitespacesAndNewlines) }

    // 何か変えたか
    private var hasChanges: Bool {
        trimmedTitle != event.title
            || description.trimmingCharacters(in: .whitespacesAndNewlines) != event.description
            || isPlaceChanged
    }

    // 集合場所(名前か位置)を変えたか
    private var isPlaceChanged: Bool {
        guard let pickedCoordinate else { return false }
        let moved = CLLocation(latitude: pickedCoordinate.latitude, longitude: pickedCoordinate.longitude)
            .distance(from: CLLocation(latitude: event.latitude, longitude: event.longitude)) > 1
        return trimmedPlace != event.placeName || moved
    }

    // Supabase の制限(イベント名40字・場所60字・コメント300字)に合わせる
    private var canSave: Bool {
        !isSaving
            && hasChanges
            && (1...40).contains(trimmedTitle.count)
            && (1...60).contains(trimmedPlace.count)
            && description.count <= 300
            && pickedCoordinate != nil
    }

    // MARK: - 保存

    private func save() {
        guard let coordinate = pickedCoordinate else { return }
        Task {
            isSaving = true
            let error = await eventStore.update(
                event,
                title: trimmedTitle,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                placeName: trimmedPlace,
                coordinate: coordinate
            )
            isSaving = false
            if let error {
                errorMessage = error
            } else {
                dismiss()
            }
        }
    }
}

#Preview {
    EditEventView(event: sampleEvents[0])
        .environment(EventStore(events: sampleEvents))
        .environment(LocationManager())
        .environment(AuthManager())
}
