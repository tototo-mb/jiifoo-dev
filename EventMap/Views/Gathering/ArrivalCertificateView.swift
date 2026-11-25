import SwiftUI
import MapKit
import AVFoundation

// 到着したときに開く「到着の記念写真」の画面(証明書がわり)
// 1. カメラで1枚撮る(承諾するまでは撮り直せる)
//    カメラを許可していない・キャンセルしたときは、会場の地図を代わりに使う
// 2. 「承諾」を押すと、写真の右下にスタンプが「ドン」と押される
// 3. 写真を保存する(マイページの過去のイベントのサムネイルになる)
struct ArrivalCertificateView: View {
    let event: CertificateEvent
    var onFinished: () -> Void = {}     // 閉じたときに呼ぶ(写真の表示を読み直すなど)

    @Environment(\.dismiss) private var dismiss

    private enum Step { case starting, confirm, stamping, done }
    @State private var step: Step = .starting
    @State private var photo: UIImage?             // 撮った写真(または会場の地図)
    @State private var isMapImage = false          // カメラが使えず、会場の地図にしたか
    @State private var showCamera = false
    @State private var showCameraNotice = false    // 撮影前の注意(このイベントで初めてのとき)
    @State private var isStamped = false           // スタンプが押されたか
    @State private var isUploading = false
    @State private var uploadFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let photo {
                // 写真(右下にスタンプを押す)
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .bottomTrailing) {
                        if step == .stamping || step == .done {
                            CertificateStampLayer(stamp: event.stamp, isStamped: isStamped)
                        }
                    }
                    .padding(.horizontal)
            } else {
                ProgressView("準備しています…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .safeAreaInset(edge: .top) {
            Text(step == .done ? "到着の記念を残しました" : "到着の記念に、1枚撮りましょう")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            bottomButtons
                .padding()
        }
        // 押した瞬間に「ドン」と振動
        .sensoryFeedback(.impact(weight: .heavy), trigger: isStamped)
        .task { start() }
        // 撮影前の注意(このイベントで初めてカメラを開くときだけ)
        .alert(PhotoNotice.cameraTitle, isPresented: $showCameraNotice) {
            Button("OK") {
                PhotoNotice.markCameraNoticeSeen(eventID: event.id)
                Task { await openCameraIfAllowed() }
            }
        } message: {
            Text(PhotoNotice.cameraMessage)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(onCapture: { image in
                photo = image
                isMapImage = false
                step = .confirm
            }, onCancel: {
                // はじめての撮影でキャンセルしたら、会場の地図にする(撮り直しのキャンセルは前の写真のまま)
                if photo == nil {
                    Task { await useMapImage() }
                }
            })
            .ignoresSafeArea()
        }
        .alert("保存できませんでした", isPresented: $uploadFailed) {
            Button("もう一度") { Task { await upload() } }
            Button("閉じる", role: .cancel) { close() }
        } message: {
            Text("通信状況を確認してください")
        }
    }



    // 下のボタン(段階ごとに変わる)
    @ViewBuilder
    private var bottomButtons: some View {
        switch step {
        case .starting:
            EmptyView()
        case .confirm:
            VStack(spacing: 12) {
                if isMapImage {
                    Text("カメラが使えないため、会場の地図を記念の画像にします")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                }
                HStack(spacing: 12) {
                    if !isMapImage {
                        Button("撮り直す") { showCamera = true }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                    Button("承諾") { accept() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .font(.headline)
            }        
            case .stamping:
            ProgressView("保存しています…")
                .tint(.white)
                .foregroundStyle(.white)
        case .done:
            Button("閉じる") { close() }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .font(.headline)
        }
    }

    // MARK: - 処理

    // はじめに:このイベントで初めてなら注意を出してから、カメラへ
    private func start() {
        if PhotoNotice.hasSeenCameraNotice(eventID: event.id) {
            Task { await openCameraIfAllowed() }
        } else {
            showCameraNotice = true
        }
    }

    // カメラが使えるならカメラを開く。使えなければ会場の地図にする
    private func openCameraIfAllowed() async {
        #if targetEnvironment(simulator)
        showCamera = true   // シミュレーターはカメラがないので、写真ライブラリから選ぶ
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            // まだ聞いていなければ、ここで許可を聞く
            if await AVCaptureDevice.requestAccess(for: .video) {
                showCamera = true
            } else {
                await useMapImage()
            }
        default:
            await useMapImage()   // 許可していない
        }
        #endif
    }

    // 会場の地図を、記念の画像にする
    private func useMapImage() async {
        photo = await VenueMapImage.make(center: event.coordinate)
        isMapImage = true
        step = .confirm
    }

    // 承諾:スタンプを押して、保存する
    private func accept() {
        step = .stamping
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
                isStamped = true
            }
        }
        Task { await upload() }
    }

    // 写真を保存する(到着写真の場所: events/<イベントID>/arrival-<ユーザーID>.jpg)
    private func upload() async {
        guard let photo else { return }
        isUploading = true
        defer { isUploading = false }
        guard let userID = await JiifooAPI.currentUserID() else {
            uploadFailed = true
            return
        }
        do {
            try await PhotoStorage.upload(photo, to: PhotoStorage.arrivalPath(eventID: event.id, userID: userID))
            try? await Task.sleep(for: .seconds(1))   // スタンプを見る時間
            step = .done
        } catch {
            print("到着写真の保存に失敗:", error)
            uploadFailed = true
        }
    }

    private func close() {
        onFinished()
        dismiss()
    }
}

// 写真の右下に押すスタンプ(押すときの動きつき)
// 到着の記念写真の画面と、設定の「写真のテスト」で使う
struct CertificateStampLayer: View {
    let stamp: ParticipationStamp
    let isStamped: Bool          // false → true になると「ドン」と押される

    var body: some View {
        CertificateStampBadge(stamp: stamp)
            .frame(width: 140)
            .padding(12)
            // 押す前：大きく・傾いて・見えない → 押した後：元の大きさ
            .scaleEffect(isStamped ? 1 : 2.5, anchor: .bottomTrailing)
            .rotationEffect(.degrees(isStamped ? 0 : -20))
            .opacity(isStamped ? 1 : 0)
    }
}
// 到着の記念写真に必要なイベントの情報(時間厳守型・途中参加型の両方から作る)
struct CertificateEvent: Identifiable {
    let id: UUID
    let title: String
    let startsAt: Date
    let isCorporate: Bool
    let coordinate: CLLocationCoordinate2D
    let organizerName: String?

    // 写真に押すスタンプ
    var stamp: ParticipationStamp {
        ParticipationStamp(eventID: id, title: title, organizerName: organizerName,
                           date: startsAt, isCorporate: isCorporate)
    }
}

extension CertificateEvent {
    // 時間厳守型(集合モードで到着したとき)
    init(event: GatheringEvent, organizerName: String?) {
        self.init(id: event.id, title: event.title, startsAt: event.startsAt,
                  isCorporate: event.kind == "corporate", coordinate: event.coordinate,
                  organizerName: organizerName)
    }
}

struct CertificateStampBadge: View {
    let stamp: ParticipationStamp

    var body: some View {
        // スタンプの形だけ白く塗る(少し透ける白。まわりの白い余白はなし)
        ParticipationStampView(stamp: stamp, paper: .white.opacity(0.85))
            .environment(\.colorScheme, .light)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}

    

// 会場の地図の画像を作る(カメラが使えないときの代わり)
enum VenueMapImage {
    static func make(center: CLLocationCoordinate2D) async -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, latitudinalMeters: 400, longitudinalMeters: 400)
        options.size = CGSize(width: 360, height: 480)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)

        let renderer = UIGraphicsImageRenderer(size: options.size)
        guard let snapshot = await snapshot(options: options) else {
            // 地図が作れなかったときは、灰色の画像
            return renderer.image { context in
                UIColor.systemGray4.setFill()
                context.fill(CGRect(origin: .zero, size: options.size))
            }
        }
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)
            // 会場の場所に赤い丸
            let point = snapshot.point(for: center)
            let circle = UIBezierPath(ovalIn: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
            UIColor.systemRed.setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = 4
            circle.stroke()
        }
    }

    // 地図の画像を撮る(電波が悪いときに待ち続けないよう、20秒で諦めて nil を返す)
    private static func snapshot(options: MKMapSnapshotter.Options) async -> MKMapSnapshotter.Snapshot? {
        let snapshotter = MKMapSnapshotter(options: options)
        let state = SnapshotState()
        return await withCheckedContinuation { continuation in
            // 地図ができたとき
            snapshotter.start(with: .main) { snapshot, _ in
                guard !state.isFinished else { return }
                state.isFinished = true
                continuation.resume(returning: snapshot)
            }
            // 20秒たってもできなければ諦める
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                guard !state.isFinished else { return }
                state.isFinished = true
                snapshotter.cancel()
                continuation.resume(returning: nil)
            }
        }
    }

    // 「もう終わったか」の目印(地図ができた・諦めたの、先に来た方だけを使う)
    private final class SnapshotState: @unchecked Sendable {
        var isFinished = false
    }
}
