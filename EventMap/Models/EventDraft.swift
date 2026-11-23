import Foundation
import CoreLocation

// 作成途中のイベント(下書き)
// 1つだけ、この iPhone の中(UserDefaults)に保存する
struct EventDraft: Codable {
    var title: String
    var description: String
    var placeName: String
    var startsAt: Date
    var hasCapacityLimit: Bool
    var capacity: Int
    var joinType: JoinType
    var durationHours: Int
    var photoEndsAt: Date
    var latitude: Double?        // 地図で選んだ場所(選んでいなければ nil)
    var longitude: Double?

    // 選んだ場所(緯度と経度の両方があるときだけ)
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - 保存・読み込み・削除

    // 保存するときの名前
    private static let key = "eventDraft"

    // 保存してある下書きを読む(なければ nil)
    static func load() -> EventDraft? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(EventDraft.self, from: data)
    }

    // 下書きを保存する(前の下書きは上書きされる)
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    // 下書きを消す
    static func delete() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}