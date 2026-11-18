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

    var errorDescription: String? {
        switch self {
        case .compressFailed: return "写真を変換できませんでした"
        case .decodeFailed: return "写真を読み込めませんでした"
        }
    }
}
