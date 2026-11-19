import SwiftUI
import UIKit

// カメラを開いて写真を1枚撮る画面
// アプリ内で撮った写真だけを使うため、実機ではカメラだけ(写真ライブラリからは選べない)
// シミュレーターにはカメラがないので、動作確認用にライブラリから選ぶ
struct CameraPicker: UIViewControllerRepresentable {
    // 撮れたときに呼ばれる(キャンセルしたときは呼ばれない)
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        #if targetEnvironment(simulator)
        picker.sourceType = .photoLibrary   // シミュレーターだけ
        #else
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo   // 写真だけ(動画は撮らない)
        #endif

        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
