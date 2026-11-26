import SwiftUI

// マイページの「過去に参加したイベント」のマス
// 到着の記念写真があれば「枠タイプのスタンプを押した写真」、なければ今までの参加スタンプを出す


// マス1つ分の見た目（記念写真と同じ縦横比 340：290）
//   写真あり → 枠タイプのスタンプを押した記念写真（到着のときと同じ見た目）
//   写真なし → 今までの参加スタンプ
struct CertificateTile: View {
    let stamp: ParticipationStamp
    let photo: UIImage?

    var body: some View {
        // 記念写真と同じ比率の透明な枠を作って、その上に写真(またはスタンプ)を重ねる
        Color.clear
            .aspectRatio(CertificateFrame.aspect, contentMode: .fit)
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()   // 枠いっぱいに広げる(はみ出た部分は下で切る)
                } else {
                    ParticipationStampView(stamp: stamp)
                        .padding(6)
                }
            }
            .overlay {
                // 写真の上に、枠タイプのスタンプを押した状態で重ねる（マスの大きさにぴったり合わせる）
                if photo != nil {
                    CertificateFrameLayer(stamp: stamp, isStamped: true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())   // 透明なところもタップできるように
    }
}

// マイページで使うマス(自分の到着写真を読み込む)
struct CertificateThumbnail: View {
    let event: PastEvent

    @State private var photo: UIImage?     // 到着写真(ないときは nil のまま)

    // 一度読み込んだマスの写真(縮小版)を、アプリを閉じるまで覚えておく
    // (タブを切り替えるたびにフルサイズの写真をダウンロードし直さないため)
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        CertificateTile(stamp: ParticipationStamp(event: event), photo: photo)
            .task(id: event.id) {
                let key = event.id.uuidString as NSString
                if let cached = Self.cache.object(forKey: key) {
                    photo = cached
                    return
                }
                guard let userID = await JiifooAPI.currentUserID() else { return }
                // 写真がないイベントは読み込みに失敗するので、nil のまま(スタンプを出す)
                guard let image = try? await PhotoStorage.downloadImage(
                    path: PhotoStorage.arrivalPath(eventID: event.id, userID: userID)) else { return }
                // マスに出すだけなので、小さくしてから表示する(1600px のままだと重い)
                let thumbnail = await image.byPreparingThumbnail(ofSize: CGSize(width: 600, height: 600)) ?? image
                Self.cache.setObject(thumbnail, forKey: key)
                photo = thumbnail
            }
    }
}