import UIKit

// 写真の保護(スクリーンショットを撮られたときの注意)
// 写真が画面に出ている間にスクショが撮られたら、注意の通知を出す
// ※ iPhone ではスクショそのものは止められないので、撮られた「あと」に知らせる
@MainActor
final class PhotoProtection {
    static let shared = PhotoProtection()

    private var visiblePhotoCount = 0          // 今、画面に出ている写真の数
    private var observer: NSObjectProtocol?

    private init() {
        // スクショが撮られたら iPhone が知らせてくれる
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                PhotoProtection.shared.screenshotTaken()
            }
        }
    }

    // StoredPhotoView が表示された・消えたときに呼ぶ
    func photoAppeared() { visiblePhotoCount += 1 }
    func photoDisappeared() { visiblePhotoCount = max(0, visiblePhotoCount - 1) }

    // 写真が出ているときにスクショされたら、注意の通知を出す
    private func screenshotTaken() {
        guard visiblePhotoCount > 0 else { return }
        Task { await NotificationManager.notifyScreenshotWarning() }
    }
}