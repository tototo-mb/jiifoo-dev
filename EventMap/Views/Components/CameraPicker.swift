import SwiftUI
import UIKit

// カメラを開いて写真を1枚撮る画面
// アプリ内で撮った写真だけを使うため、実機ではカメラだけ(写真ライブラリからは選べない)
// シミュレーターにはカメラがないので、動作確認用にライブラリから選ぶ
struct CameraPicker: UIViewControllerRepresentable {
    // 撮れたときに呼ばれる(キャンセルしたときは呼ばれない)
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void = {}
    // 撮影枠の縦横比（横÷縦）。指定すると、カメラ画面にその比率の枠を出す
    // ※ 枠は目安。撮った写真は呼んだ側で PhotoCrop.centerCrop を使って同じ比率に切り抜く
    var guideAspect: CGFloat? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        #if targetEnvironment(simulator)
        picker.sourceType = .photoLibrary   // シミュレーターだけ
        #else
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo   // 写真だけ(動画は撮らない)
        if let guideAspect {
            let overlay = CameraGuideOverlay(aspect: guideAspect)
            overlay.frame = UIScreen.main.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            picker.cameraOverlayView = overlay
        }
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
            parent.onCancel()
            parent.dismiss()
        }
    }
}

// カメラ画面に重ねる撮影枠（枠の外を暗くする）
// カメラの映像は横幅いっぱい・縦横比 3：4 で画面の中央あたりに出るので、その中央に枠を置く
// ※ 機種によってずれる場合は previewCenterOffset で上下を調整する
final class CameraGuideOverlay: UIView {
    let aspect: CGFloat
    var previewCenterOffset: CGFloat = -20   // カメラの映像の中心が画面の中心からどれだけ上か(pt)

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let label = UILabel()

    init(aspect: CGFloat) {
        self.aspect = aspect
        super.init(frame: .zero)
        isUserInteractionEnabled = false     // シャッターなどのボタンはそのまま押せる
        backgroundColor = .clear
        dimLayer.fillRule = .evenOdd
        dimLayer.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.strokeColor = UIColor.white.cgColor
        borderLayer.lineWidth = 2
        layer.addSublayer(dimLayer)
        layer.addSublayer(borderLayer)
        label.text = "枠の中が記念写真になります"
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.black.cgColor
        label.layer.shadowOpacity = 0.6
        label.layer.shadowRadius = 3
        label.layer.shadowOffset = .zero
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let previewHeight = width * 4 / 3
        let previewTop = (bounds.height - previewHeight) / 2 + previewCenterOffset
        let preview = CGRect(x: 0, y: previewTop, width: width, height: previewHeight)

        let guideHeight = width / aspect
        let guide = CGRect(x: 0, y: preview.midY - guideHeight / 2, width: width, height: guideHeight)

        // カメラの映像のうち、枠の外（上下）だけを暗くする
        let dim = UIBezierPath(rect: preview)
        dim.append(UIBezierPath(rect: guide))
        dimLayer.path = dim.cgPath
        borderLayer.path = UIBezierPath(rect: guide.insetBy(dx: 1, dy: 1)).cgPath

        label.frame = CGRect(x: 0, y: guide.minY - 28, width: width, height: 20)
    }
}
