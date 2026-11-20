import SwiftUI

// =====================================================
// 参加スタンプ（パスポートの入国スタンプ風。デザイン案D）
//
//   ParticipationStampView(stamp: ParticipationStamp(event: 過去のイベント))
//
// ・個人イベントは赤、法人イベントは紺のインク
// ・決まった大きさ（340×290）で描いて、置いた場所の大きさに合わせて縮める
//   → 一覧の小さいマスでも、詳細画面の大きい表示でも同じ見た目になる
// ・背景は透明（画面の背景がそのまま見える）
// ・ダークモードでは、暗い背景でも読めるように法人のインクを白にする（個人は赤のまま）
// =====================================================

// スタンプに載せる内容
struct ParticipationStamp: Hashable {
    let eventID: UUID
    let title: String
    let organizerName: String?
    let date: Date
    let isCorporate: Bool

    init(eventID: UUID, title: String, organizerName: String?, date: Date, isCorporate: Bool) {
        self.eventID = eventID
        self.title = title
        self.organizerName = organizerName
        self.date = date
        self.isCorporate = isCorporate
    }

    init(event: PastEvent) {
        self.init(eventID: event.id,
                  title: event.title,
                  organizerName: event.organizerName,
                  date: event.startsAt,
                  isCorporate: event.kind == "corporate")
    }

    // イベントIDの先頭8文字（大文字）。例: 3F9A21C0
    var shortID: String {
        String(eventID.uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).uppercased()
    }

    // 「17 NOV 2026」の形の日付
    var dateText: String {
        Self.dateFormatter.string(from: date).uppercased()
    }

    // 押した角度（イベントごとに決まった、少しだけ傾いた角度。-4〜4度）
    var tilt: Double {
        Double(Int(eventID.uuid.0) % 9) - 4
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy"
        return f
    }()
}

// スタンプのインクの色（ライト / ダークで変える）
enum StampInk {
    // ライトモード
    static let individual = Color(red: 0.788, green: 0.200, blue: 0.169)  // #C9332B 赤
    static let corporate  = Color(red: 0.137, green: 0.243, blue: 0.545)  // #233E8B 紺
    // ダークモード（黒い背景で読めるように）
    static let individualDark = Color(red: 1.000, green: 0.322, blue: 0.282)  // #FF5248 明るい赤
    static let corporateDark  = Color.white                                  // 白

    static func color(isCorporate: Bool, scheme: ColorScheme) -> Color {
        switch (isCorporate, scheme) {
        case (true, .dark):  return corporateDark
        case (false, .dark): return individualDark
        case (true, _):      return corporate
        default:             return individual
        }
    }
}

struct ParticipationStampView: View {
    let stamp: ParticipationStamp
    var tilted = true      // 少し傾けて「押した」感じにするか

    // デザインの大きさ（この大きさで描いてから縮める）
    private static let designSize = CGSize(width: 340, height: 290)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.designSize.width,
                            geo.size.height / Self.designSize.height)
            StampFace(stamp: stamp)
                .frame(width: Self.designSize.width, height: Self.designSize.height)
                .scaleEffect(scale)
                .rotationEffect(.degrees(tilted ? stamp.tilt : 0))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(Self.designSize.width / Self.designSize.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "参加スタンプ \(stamp.title) \(stamp.date.formatted(date: .long, time: .omitted))"
        if let name = stamp.organizerName { text += " 主催 \(name)" }
        return text
    }
}

// スタンプの絵（340×290 の中に、デザイン案Dと同じ位置で並べる）
private struct StampFace: View {
    let stamp: ParticipationStamp
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ink = StampInk.color(isCorporate: stamp.isCorporate, scheme: colorScheme)

        ZStack {
            // 二重の枠
            RoundedRectangle(cornerRadius: 20)
                .stroke(ink, lineWidth: 6)
                .frame(width: 324, height: 274)
            RoundedRectangle(cornerRadius: 10)
                .stroke(ink, lineWidth: 2)
                .frame(width: 298, height: 248)

            // 左上：ロゴ（アイコン＋文字）
            JiifooLogoShape()
                .fill(ink, style: FillStyle(eoFill: true))
                .frame(width: 36, height: 38)
                .position(x: 58, y: 46)
            JiifooWordmarkShape()
                .fill(ink, style: FillStyle(eoFill: true))
                .frame(width: 72, height: 32)
                .position(x: 118, y: 49)

            // 右上：イベントID
            Text("ID \(stamp.shortID)")
                .font(.system(size: 15, weight: .medium).width(.condensed))
                .tracking(2)
                .frame(width: 140, alignment: .trailing)
                .position(x: 226, y: 52)

            // ARRIVED と日付
            Text("ARRIVED")
                .font(.system(size: 54, weight: .bold).width(.condensed))
                .tracking(5)
                .position(x: 170, y: 101)
            Text(stamp.dateText)
                .font(.system(size: 24, weight: .medium).width(.condensed))
                .tracking(3)
                .position(x: 170, y: 144)

            Rectangle()
                .fill(ink)
                .frame(width: 252, height: 2)
                .position(x: 170, y: 168)

            // イベント名（長い名前は縮めて1行に収める）
            Text(stamp.title)
                .font(.system(size: 28, weight: .heavy))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 264)
                .position(x: 170, y: 198)

            // 点線
            Path { p in
                p.move(to: CGPoint(x: 70, y: 226))
                p.addLine(to: CGPoint(x: 270, y: 226))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))

            // 主催者の名前
            Text("主催　\(stamp.organizerName ?? "—")")
                .font(.system(size: 15, weight: .bold))
                .tracking(2)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 240)
                .position(x: 170, y: 247)
        }
        .foregroundStyle(ink)
        .frame(width: 340, height: 290)
    }
}

// 余白をつけたスタンプ（一覧のマス・詳細画面で使う）。背景は透明
struct StampOnPaper: View {
    let stamp: ParticipationStamp
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 12   // 以前の台紙の角丸（今は使っていない。呼び出し側との互換のため残す）

    var body: some View {
        ParticipationStampView(stamp: stamp)
            .padding(padding)
            .contentShape(Rectangle())   // 透明でも、余白を含めた全体をタップできるように
    }
}

#Preview("スタンプ") {
    VStack(spacing: 24) {
        StampOnPaper(stamp: ParticipationStamp(
            eventID: UUID(), title: "缶蹴り", organizerName: "ユーザー名",
            date: .now, isCorporate: false))
        StampOnPaper(stamp: ParticipationStamp(
            eventID: UUID(), title: "大原口喧嘩祭", organizerName: "法人名",
            date: .now, isCorporate: true))
    }
    .padding()
}

#Preview("スタンプ（ダークモード）") {
    VStack(spacing: 24) {
        StampOnPaper(stamp: ParticipationStamp(
            eventID: UUID(), title: "缶蹴り", organizerName: "ユーザー名",
            date: .now, isCorporate: false))
        StampOnPaper(stamp: ParticipationStamp(
            eventID: UUID(), title: "大原口喧嘩祭", organizerName: "法人名",
            date: .now, isCorporate: true))
    }
    .padding()
    .preferredColorScheme(.dark)
}
