import SwiftUI

// マイページの「過去に参加したイベント」のマス
// 到着の記念写真があれば「写真＋右下にスタンプ」、なければ今までの参加スタンプを出す


// マス1つ分の見た目(正方形。写真があれば写真＋右下にスタンプ、なければスタンプだけ)
struct CertificateTile: View {
    let stamp: ParticipationStamp
    let photo: UIImage?
        var body: some View {
        // 正方形の透明な枠を作って、その上に写真(またはスタンプ)を重ねる
        Color.clear
            .aspectRatio(1, contentMode: .fit)            
            .overlay {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()   // 枠いっぱいに広げる(はみ出た部分は下で切る)
                } else {
                    ParticipationStampView(stamp: stamp)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if photo != nil {
                    CertificateStampBadge(stamp: stamp)
                        .frame(width: 72)
                        .padding(6)
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

    var body: some View {
        CertificateTile(stamp: ParticipationStamp(event: event), photo: photo)
            .task(id: event.id) {
                guard let userID = await JiifooAPI.currentUserID() else { return }
                // 写真がないイベントは読み込みに失敗するので、nil のまま(スタンプを出す)
                photo = try? await PhotoStorage.downloadImage(
                    path: PhotoStorage.arrivalPath(eventID: event.id, userID: userID))
            }
    }
}