import UIKit
import Supabase

// 写真の保存・表示をまとめた所(今は Supabase Storage を使う)
// 保存先を変える(例: Cloudflare R2)ときは、このファイルの中だけ直せばよいようにしている
// ※ DB には URL ではなく「保存場所の名前(パス)」を記録すること
enum PhotoStorage {
    // Supabase Storage のバケット名(非公開。見られる人は Supabase 側のルールで制限)
    static let bucket = "event-photos"

    // MARK: - 保存場所の名前(パス)

    // 到着したときの写真: events/<イベントID>/arrival-<ユーザーID>.jpg
    static func arrivalPath(eventID: UUID, userID: UUID) -> String {
        "events/\(eventID.uuidString.lowercased())/arrival-\(userID.uuidString.lowercased()).jpg"
    }

    // 動作確認用(設定画面の「写真のテスト」で使う): test/<ユーザーID>/test.jpg
    static func testPath(userID: UUID) -> String {
        "test/\(userID.uuidString.lowercased())/test.jpg"
    }

    // MARK: - 保存・表示・削除

    // 写真を縮小・圧縮して保存する(同じ名前があれば上書き)
    static func upload(_ image: UIImage, to path: String) async throws {
        guard let data = compress(image) else { throw PhotoError.compressFailed }
        _ = try await supabase.storage
            .from(bucket)
            .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
    }

    // 表示用の一時的な URL(1時間だけ有効。非公開バケットなので毎回これで取る)
    static func displayURL(for path: String) async throws -> URL {
        try await supabase.storage
            .from(bucket)
            .createSignedURL(path: path, expiresIn: 60 * 60)
    }

    // 写真を直接ダウンロードして画像にする(表示用)
    static func downloadImage(path: String) async throws -> UIImage {
        let data = try await supabase.storage
            .from(bucket)
            .download(path: path)
        guard let image = UIImage(data: data) else { throw PhotoError.decodeFailed }
        return image
    }

    // このイベントで到着時の写真を撮った人(ユーザーID)の一覧
    static func arrivalPhotoUserIDs(eventID: UUID) async throws -> Set<UUID> {
        let files = try await supabase.storage
            .from(bucket)
            .list(path: "events/\(eventID.uuidString.lowercased())")
        // ファイル名 arrival-<ユーザーID>.jpg からユーザーIDを取り出す
        return Set(files.compactMap { file -> UUID? in
            guard file.name.hasPrefix("arrival-"), file.name.hasSuffix(".jpg") else { return nil }
            return UUID(uuidString: String(file.name.dropFirst("arrival-".count).dropLast(".jpg".count)))
        })
    }

    // 写真を消す
    static func delete(path: String) async throws {
        _ = try await supabase.storage
            .from(bucket)
            .remove(paths: [path])
    }

    // MARK: - 思い出の写真(1人1イベント最大5枚)

    // 1人1イベントで撮れる枚数(Supabase の reserve_photo_slot と同じ数にする)
    static let maxMemoryPhotos = 5

    // 思い出の写真を1枚増やす:枠を取る → 保存。保存に失敗したら枠を返す
    // 成功したら保存場所の名前を返す
    static func addMemoryPhoto(_ image: UIImage, eventID: UUID) async throws -> String {
        let result = try await JiifooAPI.reservePhotoSlot(eventId: eventID)
        switch result {
        case "limit_reached": throw PhotoError.limitReached
        case "not_member":    throw PhotoError.notMember
        default: break
        }
        guard result.hasPrefix("events/") else { throw PhotoError.unknown(result) }

        do {
            try await upload(image, to: result)
        } catch {
            _ = try? await JiifooAPI.deleteEventPhoto(path: result)   // 枠を返す(枚数に数えない)
            throw error
        }
        return result
    }

    // 撮り直す:同じ名前に上書きする(枚数は増えない)
    static func retakeMemoryPhoto(_ image: UIImage, path: String) async throws {
        try await upload(image, to: path)
    }

    // 思い出の写真を消す:ファイル → 記録の順に消す
    // (ファイルを消せなかったときは記録を残すので、写真と記録がずれない)
    static func deleteMemoryPhoto(path: String) async throws {
        try await delete(path: path)
        _ = try await JiifooAPI.deleteEventPhoto(path: path)
    }


    // MARK: - 縮小・圧縮

    // 長い辺を maxLength(px) までに縮めて JPEG にする
    // iPhone の写真(数MB)が 1枚 300〜500KB くらいになる
    static func compress(_ image: UIImage, maxLength: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        let size = image.size
        let scale = min(1, maxLength / max(size.width, size.height))
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // 画面の倍率をかけない(実際のピクセル数を newSize にする)
        let resized = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

enum PhotoError: LocalizedError {
    case compressFailed
    case decodeFailed
    case limitReached        // すでに5枚撮り終わっている
    case notMember           // このイベントの参加者ではない
    case unknown(String)     // それ以外(サーバーからの返事をそのまま入れる)


    var errorDescription: String? {
        switch self {
        case .compressFailed: return "写真を変換できませんでした"
        case .decodeFailed: return "写真を読み込めませんでした"
        case .limitReached: return "このイベントで撮れるのは\(PhotoStorage.maxMemoryPhotos)枚までです"
        case .notMember: return "このイベントの参加者だけが撮影できます"
        case .unknown(let result): return "写真を保存できませんでした(\(result))"

        }
    }
}
