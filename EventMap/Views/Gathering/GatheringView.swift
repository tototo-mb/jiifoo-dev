import SwiftUI
import MapKit

// 集合モードの画面
// ・集合場所の地図(光の柱)と、自分の現在地
// ・開始までのカウントダウンと、集合場所までの距離
// ・メンバーの到着状況(15秒ごとに更新)
// ・集合場所から100m以内で「到着しました」を押せる
struct GatheringView: View {
    let event: GatheringEvent

    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss

    @State private var members: [GatheringMember] = []
    @State private var myStatus: String
    @State private var isCheckingIn = false
    @State private var message: String?
    @State private var camera: MapCameraPosition

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ---- 地図 ----
                Map(position: $camera) {
                    UserAnnotation()
                    MapCircle(center: event.coordinate, radius: Self.checkInRadius)
                        .foregroundStyle(.orange.opacity(0.15))
                        .stroke(.orange, lineWidth: 1)
                    Annotation(event.placeName, coordinate: event.coordinate) {
                        //GatherBeaconView()
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
                                Text(member.checkedIn ? "到着" : "移動中")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(event.title)
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
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            .sensoryFeedback(.success, trigger: isCheckedIn)
            .alert(message ?? "", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
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
                checkIn()
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
        }
    }

    // MARK: - 処理

    private func loadMembers() async {
        if let list = try? await JiifooAPI.eventMembers(eventId: event.id) {
            members = list
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
