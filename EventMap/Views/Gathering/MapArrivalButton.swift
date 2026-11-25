import SwiftUI

// マップの下に出す「到着しました」ボタン
// (集合場所・会場の100m以内にいて、まだ到着していないときだけ地図に出す。時間厳守型・途中参加型の両方)
// 押すと到着を記録する。初めての到着なら、地図の側で「到着の記念写真」の画面を開く
struct MapArrivalButton: View {
    let eventID: UUID
    var onArrived: (_ isFirst: Bool) async -> Void   // 到着できたら呼ぶ(isFirst: 初めての到着か)

    @Environment(LocationManager.self) private var locationManager

    @State private var isCheckingIn = false        // 送信中か
    @State private var message: String?            // うまくいかなかったときのお知らせ
    @State private var arrived = false             // 到着できたか(振動用)

    var body: some View {
        Button {
            checkIn()
        } label: {
            HStack(spacing: 8) {
                if isCheckingIn {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "mappin.and.ellipse")
                }
                Text("到着しました")
            }
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(.orange, in: Capsule())
            .shadow(radius: 4)
        }
        .disabled(isCheckingIn)
        .sensoryFeedback(.success, trigger: arrived)
        .alert(message ?? "", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) { }
        }
    }

    // 到着を記録する(集合モード画面の checkIn と同じ)
    private func checkIn() {
        guard let here = locationManager.userLocation else { return }
        isCheckingIn = true
        Task {
            let result = (try? await JiifooAPI.checkIn(
                eventId: eventID, latitude: here.latitude, longitude: here.longitude)) ?? "error"
            switch result {
            case "ok", "already_checked_in":
                arrived = true
                await onArrived(result == "ok")   // "ok" のときだけ初めての到着
            case "too_far":
                message = "集合場所から\(Int(GatheringView.checkInRadius))m以内で押してください"
            case "not_gathering":
                message = "今は集合時間ではありません"
            case "not_member":
                message = "このイベントの参加者ではありません"
            default:
                message = "到着を記録できませんでした。通信状況を確認してください"
            }
            isCheckingIn = false
        }
    }
}