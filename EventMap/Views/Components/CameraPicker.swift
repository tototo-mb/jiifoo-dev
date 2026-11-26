import SwiftUI
import UIKit
import CoreMotion

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
//
// iPhone を横にして撮ると、写真は横長（4：3）になり、切り抜かれるのは左右の端になる。
// カメラ画面そのものは縦のまま回らないので、傾きセンサーで向きを調べて、
// 横持ちのときは枠を「幅いっぱい・縦に長い形」に変え、文字も横向きに回す。
// （画面の回転ロックがオンでも動くように、画面の向きではなく傾きセンサーを使う）
final class CameraGuideOverlay: UIView {
    // 持ち方
    private enum Hold {
        case portrait
        case landscapeLeft    // 本体の上が左を向いている（左側が下）
        case landscapeRight   // 本体の上が右を向いている（右側が下）
    }

    let aspect: CGFloat
    var previewCenterOffset: CGFloat = -20   // カメラの映像の中心が画面の中心からどれだけ上か(pt)

    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let label = UILabel()
    private let motion = CMMotionManager()
    private var hold: Hold = .portrait {
        didSet {
            guard hold != oldValue else { return }
            // 枠の形と文字の向きを、ふわっと切り替える
            UIView.animate(withDuration: 0.25) {
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
        }
    }

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

    // 画面に出ている間だけ、傾きセンサーで持ち方を調べる
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startWatchingHold()
        } else {
            motion.stopAccelerometerUpdates()
        }
    }

    private func startWatchingHold() {
        guard motion.isAccelerometerAvailable, !motion.isAccelerometerActive else { return }
        motion.accelerometerUpdateInterval = 0.2
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let g = data?.acceleration else { return }
            // 重力がどちら向きにかかっているかで持ち方を決める
            // （斜めのときにパタパタ切り替わらないよう、はっきり傾いたときだけ変える）
            if g.x < -0.65 {
                self.hold = .landscapeLeft
            } else if g.x > 0.65 {
                self.hold = .landscapeRight
            } else if abs(g.y) > 0.65 {
                self.hold = .portrait
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let previewHeight = width * 4 / 3
        let previewTop = (bounds.height - previewHeight) / 2 + previewCenterOffset
        let preview = CGRect(x: 0, y: previewTop, width: width, height: previewHeight)

        // 縦持ち：写真の横 = 画面の横 → 枠の高さ = 幅 ÷ 比率
        // 横持ち：写真の縦 = 画面の横 → 枠の高さ = 幅 × 比率
        let guideHeight = min(hold == .portrait ? width / aspect : width * aspect, previewHeight)
        let guide = CGRect(x: 0, y: preview.midY - guideHeight / 2, width: width, height: guideHeight)

        // カメラの映像のうち、枠の外（上下）だけを暗くする
        let dim = UIBezierPath(rect: preview)
        dim.append(UIBezierPath(rect: guide))
        dimLayer.path = dim.cgPath
        borderLayer.path = UIBezierPath(rect: guide.insetBy(dx: 1, dy: 1)).cgPath

        // 文字は「写真の上側」に、読める向きで置く
        switch hold {
        case .portrait:
            label.transform = .identity
            label.bounds = CGRect(x: 0, y: 0, width: width, height: 20)
            label.center = CGPoint(x: width / 2, y: guide.minY - 18)
        case .landscapeLeft:
            // 写真の上側は画面の右端
            label.transform = CGAffineTransform(rotationAngle: .pi / 2)
            label.bounds = CGRect(x: 0, y: 0, width: guide.height - 40, height: 20)
            label.center = CGPoint(x: width - 20, y: guide.midY)
        case .landscapeRight:
            // 写真の上側は画面の左端
            label.transform = CGAffineTransform(rotationAngle: -.pi / 2)
            label.bounds = CGRect(x: 0, y: 0, width: guide.height - 40, height: 20)
            label.center = CGPoint(x: 20, y: guide.midY)
        }
    }
}
