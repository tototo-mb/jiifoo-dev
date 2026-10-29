import Foundation
import Supabase

// MARK: - Supabase クライアント
// URL とキーは管理画面の「Project Settings」→「API Keys」(または「Data API」)で確認
// ※アプリに入れてよいのは publishable(anon)キーだけ。secret / service_role キーは絶対に入れない
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://wypsecmtkzgxugjlwwkj.supabase.co")!,
    supabaseKey: "sb_publishable_FRaXYjswrJ2CW2YJXR40eQ_fUHz2Cz5"
)
// MARK: - データの形(Supabase から受け取る)
nonisolated struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    let displayName: String
    let bio: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case bio
    }
}

nonisolated struct EventPin: Codable, Identifiable, Sendable {
    let id: UUID
    let creatorId: UUID
    let title: String
    let category: String
    let kind: String
    let description: String?
    let placeName: String
    let latitude: Double
    let longitude: Double
    let startsAt: Date
    let capacity: Int?
    let participantCount: Int
    let distanceM: Double

    enum CodingKeys: String, CodingKey {
        case id, title, category, kind, description, latitude, longitude, capacity
        case creatorId = "creator_id"
        case placeName = "place_name"
        case startsAt = "starts_at"
        case participantCount = "participant_count"
        case distanceM = "distance_m"
    }
}
//法人
nonisolated struct Organization:Codable,Identifiable,Hashable,Sendable{
    let id: UUID
    let name:String
}

// MARK: - データの形(Supabase に送る)

nonisolated struct NewEvent: Encodable, Sendable {
    let creatorId: UUID
    let organizationId:UUID?
    let title: String
    let category: String
    let description: String?
    let placeName: String
    let location: String      // "SRID=4326;POINT(経度 緯度)" の形式
    let startsAt: Date
    let capacity: Int?

    enum CodingKeys: String, CodingKey {
        case title, category, description, location, capacity
        case creatorId = "creator_id"
        case organizationId="organization_id"
        case placeName = "place_name"
        case startsAt = "starts_at"
    }
}

nonisolated struct CreatedEvent: Decodable, Sendable {
    let id: UUID
}
// MARK: - 機能

enum JiifooAPI {

    // 新規登録(表示名はトリガーでプロフィールに入る)
    static func signUp(email: String, password: String, displayName: String) async throws {
        try await supabase.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
    }

    // ログイン
    static func signIn(email: String, password: String) async throws {
        try await supabase.auth.signIn(email: email, password: password)
    }

    // ログアウト
    static func signOut() async throws {
        try await supabase.auth.signOut()
    }

    // 自分のプロフィールを読む
    static func myProfile() async throws -> Profile {
        let userId = try await supabase.auth.session.user.id
        return try await supabase
            .from("profiles")
            .select("id, display_name, bio")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
    }

    // イベントを作る(開始は5分後〜1時間後の範囲)
    static func createEvent(
        title: String,
        category: String,
        description: String?,
        placeName: String,
        latitude: Double,
        longitude: Double,
        startsAt: Date,
        capacity: Int?,
        organizationId:UUID?
        
    ) async throws -> UUID {
        let userId = try await supabase.auth.session.user.id
        let event = NewEvent(
            creatorId: userId,
            organizationId: organizationId,
            title: title,
            category: category,
            description: description,
            placeName: placeName,
            // PostGIS は「経度 緯度」の順なので注意
            location: "SRID=4326;POINT(\(longitude) \(latitude))",
            startsAt: startsAt,
            capacity: capacity
        )
        let created: CreatedEvent = try await supabase
            .from("events")
            .insert(event)
            .select("id")
            .single()
            .execute()
            .value
        return created.id
    }

    // 近くの募集中イベントを探す
    static func nearbyEvents(latitude: Double, longitude: Double, radiusM: Double = 800) async throws -> [EventPin] {
        try await supabase
            .rpc("nearby_events", params: [
                "lat": latitude,
                "lng": longitude,
                "radius_m": radiusM
            ])
            .execute()
            .value
    }

    // ログイン中のユーザーID(ログインしていなければ nil)
    static func currentUserID() async -> UUID? {
        try? await supabase.auth.session.user.id
    }

    // 自分が予約中(または作成した)イベントの ID 一覧
    static func myActiveEventIDs() async throws -> Set<UUID> {
        nonisolated struct Row: Decodable, Sendable { let event_id: UUID }
        guard let userId = await currentUserID() else { return [] }
        let rows: [Row] = try await supabase
            .from("participations")
            .select("event_id")
            .eq("user_id", value: userId)
            .in("status", values: ["reserved", "checked_in"])
            .execute()
            .value
        return Set(rows.map(\.event_id))
    }

    // 参加を予約する(結果: ok / full / closed / already_reserved など)
    static func reserve(eventId: UUID) async throws -> String {
        try await supabase
            .rpc("reserve_event", params: ["p_event_id": eventId])
            .execute()
            .value
    }

    // 予約をキャンセルする(結果: ok / too_late / not_reserved など)
    static func cancel(eventId: UUID) async throws -> String {
        try await supabase
            .rpc("cancel_reservation", params: ["p_event_id": eventId])
            .execute()
            .value
    }
    
    // 法人として投稿できる法人の一覧(所属していなければ空)
        static func myPostableOrganizations() async throws -> [Organization] {
            try await supabase
                .rpc("my_postable_organizations")
                .execute()
                .value
        }
}
