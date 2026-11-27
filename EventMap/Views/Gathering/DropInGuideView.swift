import SwiftUI
import MapKit

// 途中参加OK型の「集合モード」画面
// ・時間厳守型の集合画面(GatheringView)と同じく、地図の炎のボタンから開く
// ・ほかの参加者の到着状況は出さず、会場までの経路・開催時間・会場・距離だけを出す
// ・到着は今までどおり、会場の100m以内に入ると地図の画面に出る「到着しました」ボタンで行う
struct DropInGuideView: View {
    let event: Event

    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition
    @State private var route: MKRoute?   // 会場までの徒歩ルート

    init(event: Event) {
        self.event = event
        _camera = State(initialValue: .camera(MapCamera(
            centerCoordinate: event.coordinate, distance: 700, heading: 0, pitch: 45)))
    }

    private var distance: Double? { locationManager.distance(to: event.coordinate) }
    private var isCheckedIn: Bool { eventStore.isCheckedIn(event) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // ---- 地図(時間厳守型の集合画面と同じ見た目) ----
                Map(position: $camera) {
                    UserAnnotation()
                    MapCircle(center: event.coordinate, radius: EventStore.venueRadius)
                        .foregroundStyle(.orange.opacity(0.15))
                        .stroke(.orange, lineWidth: 1)

                    // 経路:濃い青(太い)の上に明るい青(細い)を重ねて、ふちどりに見せる
                    if let route {
                        MapPolyline(route.polyline)
                            .stroke(Color(red: 0.0, green: 0.36, blue: 0.85),
                                    style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                        MapPolyline(route.polyline)
                            .stroke(Color(red: 0.25, green: 0.62, blue: 1.0),
                                    style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }

                    // 会場の目印
                    Annotation(event.placeName, coordinate: event.coordinate, anchor: .bottom) {
                        GatherBeaconView()
                    }

                    // 経路の途中に所要時間の吹き出し
                    if let route, let routeMidpoint {
                        Annotation("", coordinate: routeMidpoint) {
                            Label("\(Int(route.expectedTravelTime / 60) + 1)分", systemImage: "figure.walk")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(red: 0.0, green: 0.36, blue: 0.85), in: Capsule())
                                .overlay(Capsule().stroke(.white, lineWidth: 1.5))
                        }
                    }
                }
                .mapStyle(.standard(emphasis: .muted))
                .frame(height: 300)

                // ---- 情報(参加者の到着状況は出さない) ----
                List {
                    Section {
                        LabeledContent("会場", value: event.placeName)
                        LabeledContent("開催時間", value: timeRangeText)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LabeledContent(remainingLabel(at: context.date),
                                           value: remainingText(at: context.date))
                        }
                        if let distance {
                            LabeledContent("会場まで", value: formatDistance(distance))
                        } else {
                            Text("現在地を取得しています…")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("あなたの到着", value: isCheckedIn ? "到着済み" : "まだ")
                    } footer: {
                        if !isCheckedIn {
                            Text("会場の\(Int(EventStore.venueRadius))m以内に入ると、地図の画面に「到着しました」ボタンが出ます")
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
            // 開いたら、まだ到着していなければ経路を出す
            .task {
                if !isCheckedIn { await loadRoute() }
            }
            // 到着したら経路は消す
            .onChange(of: isCheckedIn) {
                if isCheckedIn { route = nil }
            }
        }
    }

    // MARK: - 表示用の文字

    // 例:「11/27 13:00 〜 15:00」(日をまたぐときは終わりにも日付を付ける)
    private var timeRangeText: String {
        let start = event.startsAt.formatted(.dateTime.month().day().hour().minute())
        let sameDay = Calendar.current.isDate(event.startsAt, inSameDayAs: event.endsAt)
        let end = sameDay
            ? event.endsAt.formatted(.dateTime.hour().minute())
            : event.endsAt.formatted(.dateTime.month().day().hour().minute())
        return "\(start) 〜 \(end)"
    }

    private func remainingLabel(at now: Date) -> String {
        now < event.startsAt ? "開始まで" : "終了まで"
    }

    // 残り時間(例:1:05:30 / 4:32)。終わっていたら「終了しました」
    private func remainingText(at now: Date) -> String {
        let target = now < event.startsAt ? event.startsAt : event.endsAt
        let seconds = Int(target.timeIntervalSince(now))
        if seconds <= 0 { return "終了しました" }
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - 経路

    // 現在地から会場までの徒歩ルートを取得して、全体が見えるようにする
    private func loadRoute() async {
        guard let here = locationManager.userLocation else { return }
        let request = MKDirections.Request()
        request.source = MKMapItem(
            location: CLLocation(latitude: here.latitude, longitude: here.longitude),
            address: nil)
        request.destination = MKMapItem(
            location: CLLocation(latitude: event.latitude, longitude: event.longitude),
            address: nil)
        request.transportType = .walking

        guard let found = try? await MKDirections(request: request).calculate().routes.first else { return }
        route = found

        // 最低400m四方+周りに30%の余白をとって合わせる
        let rect = found.polyline.boundingMapRect
        let minSize = 400 * MKMapPointsPerMeterAtLatitude(event.latitude)
        let width = max(rect.width, minSize)
        let height = max(rect.height, minSize)
        let fitted = MKMapRect(x: rect.midX - width / 2, y: rect.midY - height / 2,
                               width: width, height: height)
        withAnimation {
            camera = .rect(fitted.insetBy(dx: -width * 0.3, dy: -height * 0.3))
        }
    }

    // 経路の真ん中あたりの点(所要時間の吹き出しを置く)
    private var routeMidpoint: CLLocationCoordinate2D? {
        guard let line = route?.polyline, line.pointCount > 0 else { return nil }
        return line.points()[line.pointCount / 2].coordinate
    }
}
