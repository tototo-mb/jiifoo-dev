import SwiftUI
import MapKit

// 地図の上で近くにあるイベントを1つにまとめたもの(クラスタリング)
// ・画面の上で radius ポイントより近いピンを同じグループにする
// ・ズームすると画面の上の距離が変わるので、まとまり方も変わる
struct EventCluster: Identifiable {
    let events: [Event]

    var id: Event.ID { events[0].id }   // 先頭のイベントのIDを、まとまりのIDにする
    var count: Int { events.count }

    // まとめたイベントの真ん中(緯度・経度の平均)
    var coordinate: CLLocationCoordinate2D {
        let latitude = events.map(\.latitude).reduce(0, +) / Double(count)
        let longitude = events.map(\.longitude).reduce(0, +) / Double(count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // 法人のイベントが1つでも入っているか(丸の色に使う)
    var hasBusiness: Bool {
        events.contains { $0.scale == .businessMode }
    }

    // イベントを、画面の上で近いものどうしでまとめる
    // camera: 今のカメラ(まだわからないときは、まとめない)
    static func make(_ events: [Event], camera: MapCamera?, proxy: MapProxy, radius: CGFloat) -> [EventCluster] {
        guard camera != nil else {
            return events.map { EventCluster(events: [$0]) }
        }
        var groups: [(point: CGPoint, events: [Event])] = []   // まとまりの最初のピンの画面の位置と、中身
        var others: [EventCluster] = []                        // 画面の位置がわからなかったもの
        for event in events {
            // 緯度・経度 → 画面の上の位置
            guard let point = proxy.convert(event.coordinate, to: .local) else {
                others.append(EventCluster(events: [event]))
                continue
            }
            // 近くにまとまりがあれば、そこに入れる。なければ新しいまとまりを作る
            if let index = groups.firstIndex(where: {
                hypot($0.point.x - point.x, $0.point.y - point.y) < radius
            }) {
                groups[index].events.append(event)
            } else {
                groups.append((point, [event]))
            }
        }
        return others + groups.map { EventCluster(events: $0.events) }
    }
}

// まとめた件数を出す丸
struct ClusterBubble: View {
    let cluster: EventCluster

    var body: some View {
        Text("\(cluster.count)")
            .font(.headline.bold())
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(cluster.hasBusiness ? Color.orange : Color.blue, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 3)
    }
}

// まとめたイベントの一覧(丸をタップすると出る)
struct ClusterListView: View {
    let events: [Event]
    var onSelect: (Event) -> Void      // イベントを選んだとき
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(events) { event in
                Button {
                    onSelect(event)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(event.placeName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(event.startsAt, format: .dateTime.month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("この場所のイベント(\(events.count)件)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}