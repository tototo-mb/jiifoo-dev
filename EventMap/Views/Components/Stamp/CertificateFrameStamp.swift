import SwiftUI
import UIKit

// =====================================================
// 到着の記念写真に押す「枠タイプ」のスタンプ（デザイン案①）
//
// ・写真はスタンプと同じ縦横比（340：290 ≒ 6：5）で撮る（CertificateFrame.aspect）
// ・写真の縁に二重の枠がぴったり重なり、上の帯にロゴとイベントID、
//   下の帯の左に ASSEMBLED・イベント名・主催者、右に年・大きな月日・時刻が入る（デザイン案①改B′ 日付を強調）
//   真ん中は写真がそのまま見える
// ・押すときの動き（烙印演出）は今までと同じ：大きく傾いた枠が「ドン」と押される
//
//   写真.overlay { CertificateFrameLayer(stamp: スタンプ, isStamped: 押したか) }
// =====================================================

enum CertificateFrame {
    // 記念写真の縦横比（横÷縦）。参加スタンプと同じ
    static let aspect: CGFloat = 340.0 / 290.0

    // デザインの大きさ（この大きさで描いてから、写真の大きさに合わせて縮める）
    static let designSize = CGSize(width: 600, height: 512)
}

// 写真の上に重ねる枠（押すときの動きつき）
struct CertificateFrameLayer: View {
    let stamp: ParticipationStamp
    let isStamped: Bool          // false → true になると「ドン」と押される

    var body: some View {
        ZStack {
            // 文字が写真に負けないように、上下の端だけ少し暗くする（押した後にふわっと出す）
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(maxHeight: .infinity)
                Color.clear.frame(maxHeight: .infinity)
                LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                    .frame(maxHeight: .infinity)
            }
            .opacity(isStamped ? 1 : 0)

            CertificateFrameStamp(stamp: stamp)
                // 押す前：大きく・傾いて・見えない → 押した後：写真ぴったり
                .scaleEffect(isStamped ? 1 : 2.5)
                .rotationEffect(.degrees(isStamped ? 0 : -20))
                .opacity(isStamped ? 1 : 0)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("参加スタンプ \(stamp.title) \(stamp.date.formatted(date: .long, time: .shortened))")
    }
}

// 枠そのもの（600×512 で描いて、置いた場所の大きさに合わせて縮める）
struct CertificateFrameStamp: View {
    let stamp: ParticipationStamp
    var ink: Color = .white.opacity(0.94)

    var body: some View {
        GeometryReader { geo in
            let size = CertificateFrame.designSize
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            face
                .frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // 文字の縦位置は「ベースライン − 文字の大きさ×0.36」で、だいたい文字の中心になる
    private func y(baseline: CGFloat, size: CGFloat) -> CGFloat { baseline - size * 0.36 }

    private var face: some View {
        ZStack {
            // 二重の枠
            RoundedRectangle(cornerRadius: 26)
                .stroke(ink, lineWidth: 8)
                .frame(width: 576, height: 488)
            RoundedRectangle(cornerRadius: 14)
                .stroke(ink, lineWidth: 2)
                .frame(width: 544, height: 456)

            // 上の帯：ロゴとイベントID
            JiifooLogoShape()
                .fill(ink, style: FillStyle(eoFill: true))
                .frame(width: 43, height: 46)
                .position(x: 71.5, y: 69)
            JiifooWordmarkShape()
                .fill(ink, style: FillStyle(eoFill: true))
                .frame(width: 92, height: 40)
                .position(x: 148, y: 72)
            Text("ID \(stamp.shortID)")
                .font(.system(size: 22, weight: .medium).width(.condensed))
                .tracking(3)
                .frame(width: 240, alignment: .trailing)
                .position(x: 430, y: y(baseline: 80, size: 22))

            // 下の帯（左）：ASSEMBLED・イベント名・主催者
            Text("ASSEMBLED")
                .font(.system(size: 22, weight: .bold).width(.condensed))
                .tracking(6)
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)
                .position(x: 210, y: y(baseline: 372, size: 22))
            Text(stamp.title)
                .font(.system(size: 44, weight: .heavy))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 326, alignment: .leading)
                .position(x: 213, y: y(baseline: 440, size: 44))
            Text("主催　\(stamp.organizerName ?? "—")")
                .font(.system(size: 16, weight: .bold))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 326, alignment: .leading)
                .position(x: 213, y: y(baseline: 468, size: 16))

            // 左右を分ける縦線
            Rectangle()
                .fill(ink)
                .frame(width: 2, height: 118)
                .position(x: 392, y: 409)

            // 下の帯（右）：年・大きな月日・時刻
            Text(stamp.yearText)
                .font(.system(size: 22, weight: .medium).width(.condensed))
                .tracking(4)
                .lineLimit(1)
                .frame(width: 140, alignment: .trailing)
                .position(x: 480, y: y(baseline: 376, size: 22))
            Text(stamp.monthDayText)
                .font(.system(size: 64, weight: .bold).width(.condensed))
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 146, alignment: .trailing)
                .position(x: 479, y: y(baseline: 440, size: 64))
            Text(stamp.timeText)
                .font(.system(size: 20, weight: .medium).width(.condensed))
                .tracking(3)
                .lineLimit(1)
                .frame(width: 140, alignment: .trailing)
                .position(x: 480, y: y(baseline: 468, size: 20))
        }
        .foregroundStyle(ink)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
    }
}

// 写真を、指定した縦横比で真ん中から切り抜く（撮影枠と同じ範囲になる）
enum PhotoCrop {
    static func centerCrop(_ image: UIImage, aspect: CGFloat) -> UIImage {
        let size = image.size   // 写真の向きを反映した大きさ
        var crop = CGSize(width: size.width, height: size.width / aspect)
        if crop.height > size.height {
            crop = CGSize(width: size.height * aspect, height: size.height)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: crop, format: format).image { _ in
            image.draw(at: CGPoint(x: -(size.width - crop.width) / 2,
                                   y: -(size.height - crop.height) / 2))
        }
    }
}

#Preview("記念写真の枠") {
    ZStack {
        Color.black.ignoresSafeArea()
        LinearGradient(colors: [.cyan, .green], startPoint: .top, endPoint: .bottom)
            .aspectRatio(CertificateFrame.aspect, contentMode: .fit)
            .overlay {
                CertificateFrameLayer(stamp: ParticipationStamp(
                    eventID: UUID(), title: "缶蹴り", organizerName: "ユーザー名",
                    date: .now, isCorporate: false), isStamped: true)
            }
            .padding()
    }
}
