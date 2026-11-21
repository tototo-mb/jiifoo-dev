import SwiftUI
import UIKit

// スクショ・画面収録に写らない画像
// iPhone のパスワード入力欄(●●●)の「スクショに写らない」性質を借りている
// ※ Apple 公式の方法ではないので、iOS が変わると効かなくなることがある
//   (そのときは普通の画像として表示されるだけで、アプリは落ちない)
struct ScreenshotProtectedImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ProtectedImageContainer {
        ProtectedImageContainer()
    }

    func updateUIView(_ uiView: ProtectedImageContainer, context: Context) {
        uiView.imageView.image = image
    }
}

// 画像を「写らない場所」に入れておく入れ物(UIKit の View)
final class ProtectedImageContainer: UIView {
    let imageView = UIImageView()
    private let secureField = UITextField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false   // タップは後ろの SwiftUI(ボタンなど)に通す
        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true

        // パスワード欄にすると、中に「スクショに写らない場所」ができる
        secureField.isSecureTextEntry = true
        if let secureArea = secureField.subviews.first {
            secureArea.subviews.forEach { $0.removeFromSuperview() }
            fill(self, with: secureArea)
            fill(secureArea, with: imageView)
        } else {
            // 取り出せなかったとき(iOS の仕組みが変わったとき)は普通に表示する
            fill(self, with: imageView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // child を parent いっぱいに広げて入れる
    private func fill(_ parent: UIView, with child: UIView) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
        ])
    }
}

// スクショに写る代わりの画像(本物の写真の後ろに置いておく)
struct ScreenshotPlaceholder: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                Text("この写真は保存できません")
                    .font(.caption2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(4)
        }
    }
}

#Preview {
    ZStack {
        ScreenshotPlaceholder()
        ScreenshotProtectedImage(image: UIImage(systemName: "photo")!)
    }
    .frame(width: 200, height: 200)
}