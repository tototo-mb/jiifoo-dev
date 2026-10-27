import SwiftUI
import MapKit

// イベントのデータ型
// Supabase の nearby_events の結果(EventPin)から作る。プレビュー用にサンプルからも作れる
struct Event: Identifiable, Sendable {
    let id: UUID
    let creatorID: UUID?          // 作成者(サンプルデータでは nil)
    let organizationID: UUID?     // 法人イベントのときだけ(今は未使用)
    let kind: String              // "normal" / "corporate"
    let title: String
    let category: String
    let description: String
    let placeName: String
    let latitude: Double
    let longitude: Double
    let scale: EventScale
    let startsAt: Date            // 開始時刻
    let capacity: Int?             // 募集人数(作成者を含まない)
    let participantCount: Int     // 現在の参加人数(作成者を含まない)

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isFull: Bool {
        guard let capacity else {return false}
        return participantCount >= capacity
    }

    // サンプルデータ・プレビュー用(既存の SampleData.swift がそのまま使える)
    init(
        id: UUID = UUID(),
        creatorID: UUID? = nil,
        organizationID: UUID? = nil,
        kind: String,
        title: String,
        category: String,
        description: String,
        placeName: String,
        latitude: Double,
        longitude: Double,
        scale: EventScale,
        startsAt: Date = Date().addingTimeInterval(30 * 60),
        capacity: Int? = 5,
        participantCount: Int = 0
    ) {
        self.id = id
        self.creatorID = creatorID
        self.organizationID = organizationID
        self.kind = kind
        self.title = title
        self.category = category
        self.description = description
        self.placeName = placeName
        self.latitude = latitude
        self.longitude = longitude
        self.scale = scale
        self.startsAt = startsAt
        self.capacity = capacity
        self.participantCount = participantCount
    }

    // Supabase から受け取ったデータから作る
    init(pin: EventPin) {
        self.init(
            id: pin.id,
            creatorID: pin.creatorId,
            kind: pin.kind,
            title: pin.title,
            category: pin.category,
            description: pin.description ?? "",
            placeName: pin.placeName,
            latitude: pin.latitude,
            longitude: pin.longitude,
            scale: pin.kind == "corporate" ? .businessMode : .privateMode,
            startsAt: pin.startsAt,
            capacity: pin.capacity,
            participantCount: pin.participantCount
        )
    }
}

// 掲載ユーザーの種類（ピンの色分けに使用）
enum EventScale: Sendable {
    case privateMode, businessMode

    var label: String {
        switch self {
        case .privateMode:  return "個人ユーザー"
        case .businessMode: return "法人ユーザー"
        }
    }

    var color: Color {
        switch self {
        case .privateMode:  return .red
        case .businessMode: return .yellow
        }
    }
}
