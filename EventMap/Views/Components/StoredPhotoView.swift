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
    //画面録画、ミラーリング中か（trueの場合は写真を隠す）
    @Environment(\.isSceneCaptured) private var isCaptured

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)   // 読み込み中・失敗時も枠が見えるように
            if isCaptured {
                // 画面収録中は写真を出さない
                VStack(spacing: 4) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                    Text("画面収録中は表示できません")
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(4)
            } else if let image {                
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
        // 写真が画面に出ている間だけ、スクショの注意を有効にする
        .onAppear { PhotoProtection.shared.photoAppeared() }
        .onDisappear { PhotoProtection.shared.photoDisappeared() }
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
