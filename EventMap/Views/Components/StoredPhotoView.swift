import SwiftUI

// 保存した写真を表示する(PhotoStorage のパスを渡すだけでよい)
// 非公開の写真なので、ログイン中のユーザーの権限で直接ダウンロードして表示する
struct StoredPhotoView: View {
    let path: String
    // 撮り直したときに表示を更新するための値(変わると読み込み直す)
    var reloadID: UUID? = nil
    // .fill: 枠いっぱいに切り抜いて表示(サムネイル向け) / .fit: 全体を表示(拡大表示向け)
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)   // 読み込み中・失敗時も枠が見えるように
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .clipped()
        .task(id: "\(path)-\(reloadID?.uuidString ?? "")") {
            failed = false
            do {
                image = try await PhotoStorage.downloadImage(path: path)
            } catch {
                guard !Task.isCancelled else { return }
                image = nil
                failed = true   // まだ写真がない・見る権限がない・通信エラー
                print("写真を表示できませんでした:", path, error)
            }
        }
    }
}
