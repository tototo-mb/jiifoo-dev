import SwiftUI
import MapKit

// 地図とピンの部分(EventMapView から切り出したもの)
// ・ピンのまとめ(クラスタ)の計算は、地図を動かし終わったときと、イベントの顔ぶれ・場所が変わったときだけ行い、
//   結果を items に覚えておく(現在地の追従やボタン操作のたびに計算し直すと重いため)
// ・ピンの大きさはズームに合わせて変えるが、Rive の描画面の大きさは変えずに .scaleEffect で拡大する
// ・「開催中」に変わったかの確認は、ピンごとではなく、ここで1つのタイマーにまとめて行う
struct EventMapLayer: View {
    @Binding var cameraPosition: MapCameraPosition
    @Binding var selectedEventID: Event.ID?
    let bounds: MapCameraBounds?
    let events: [Event]                        // 地図に出すイベント
    let showJoinableRange: Bool
    let userLocation: CLLocationCoordinate2D?
    let pinStyle: PinStyle
    let isActive: Bool                         // マップのタブを表示中か
    let photoCounts: [Event.ID: Int]           // 開催中のイベントの写真の枚数
    var onSelectPin: (Event) -> Void           // ピンを押したとき
    var onTapCluster: (EventCluster) -> Void   // まとめた丸を押したとき
    var onCameraEnd: (MapCamera, MapProxy) -> Void   // 地図を動かし終わったとき

    @State private var items: [MapAnnotationItem] = []   // 計算済みのピンとまとめた丸
    @State private var camera: MapCamera?                // 最後に動かし終わったときのカメラ
    @State private var pinScale: CGFloat = 1             // ピンの大きさ(ズームインすると大きくなる。1〜2)
    @State private var now = Date.now                    // 「開催中」かどうかを決める時刻(10秒ごとに進める)

    var body: some View {
        // 最新のイベントの中身(1回だけ作って、全部のピンで使う)
        let latest = latestEvents
        MapReader { proxy in
            Map(position: $cameraPosition, bounds: bounds, selection: $selectedEventID) {
                UserAnnotation()
                if showJoinableRange, let userLocation {
                    MapCircle(center: userLocation, radius: LocationManager.joinableRadius)
                        .foregroundStyle(.blue.opacity(0.08))
                        .stroke(.blue.opacity(0.5), lineWidth: 1.5)
                }

                ForEach(items) { item in
                    if let event = item.event {
                        pinAnnotation(for: latest[event.id] ?? event)
                    } else if let cluster = item.cluster {
                        // 2つ以上なら、件数の丸(タップで一覧)
                        Annotation("\(cluster.count)件", coordinate: cluster.coordinate) {
                            ClusterBubble(cluster: cluster)
                                .onTapGesture { onTapCluster(cluster) }
                        }
                    }
                }
            }
            .mapControls { }
            .mapStyle(.standard(elevation: .realistic,
                                emphasis: .muted,
                                pointsOfInterest: .including([
                                    .publicTransport,   // 駅・バス停
                                    .park,              // 公園
                                    .landmark,          // ランドマーク
                                    .castle,            // 城・史跡
                                    .stadium,           // スタジアム・競技場
                                    .university,        // 大学
                                    .police,            // 交番・警察
                                    .museum,
                                    .theater
                                ])))
            .onMapCameraChange(frequency: .onEnd) { context in
                camera = context.camera
                // 高さに合わせてピンの大きさを変える(動かし終わったときだけ。ふわっと)
                withAnimation(.easeOut(duration: 0.25)) {
                    pinScale = Self.pinScale(for: context.camera.distance)
                }
                updateItems(proxy: proxy)
                onCameraEnd(context.camera, proxy)
            }
            // イベントの顔ぶれ・場所が変わったときだけ、まとめ直す(最初の表示のときも)
            .onChange(of: layoutKey, initial: true) {
                updateItems(proxy: proxy)
            }
            .ignoresSafeArea()
        }
        // 開始時刻を過ぎたら「開催中」にする(10秒ごとに確かめる。全部のピンでこの1つを使う)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                now = .now
            }
        }
    }

    // ピン1つ分(1つだけのイベント)
    @MapContentBuilder
    private func pinAnnotation(for event: Event) -> some MapContent {
        Annotation(event.title, coordinate: event.coordinate, anchor: .bottom) {
            MapEventPin(eventID: event.id,
                        pinStyle: pinStyle,
                        isLive: event.startsAt <= now,
                        isSelected: selectedEventID == event.id,
                        isPlaying: isActive,
                        photoCount: photoCounts[event.id] ?? 0,
                        pinScale: pinScale)
                .onTapGesture { onSelectPin(event) }
        }
    }

    // 最新のイベントの中身(タイトル・開始時刻など)。items には古い中身が残っていることがあるので、ここから引く
    private var latestEvents: [Event.ID: Event] {
        Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // イベントの顔ぶれと場所だけから作った目印。これが変わったときだけ、まとめ直す
    // (参加人数などが変わっただけでは、まとめ直さない)
    private var layoutKey: Int {
        var hasher = Hasher()
        for event in events {
            hasher.combine(event.id)
            hasher.combine(event.latitude)
            hasher.combine(event.longitude)
        }
        return hasher.finalize()
    }

    // 近くのピンをまとめる(ピンが大きいほど、まとめる距離も広く)
    private func updateItems(proxy: MapProxy) {
        items = MapAnnotationItem.make(events, camera: camera, proxy: proxy, radius: 40 * pinScale)
    }

    // カメラの高さに合わせたピンの大きさ(近づくほど大きく。最大2倍)
    // 平方根(sqrt)を使って、近づいたときに急に大きくなりすぎないようにする
    static func pinScale(for distance: Double) -> CGFloat {
        let scale = (EventMapView.maxZoomOutDistance / max(distance, 1)).squareRoot()
        return CGFloat(min(max(scale, 1), 2))
    }
}

// 地図のピン1本(タップは外側で付ける)
// ・中身を数値・真偽値だけにしているので、入力が前と同じなら SwiftUI が描き直しを省いてくれる
// ・Rive の描画面はいつも同じ大きさ(baseSize)にしておき、ズームの拡大は .scaleEffect で見た目だけ変える
//   (.frame の大きさを変えると、アニメーション中の毎フレーム Rive の描画面が作り直されて重いため)
struct MapEventPin: View {
    let eventID: UUID
    let pinStyle: PinStyle
    let isLive: Bool          // 開催中か
    let isSelected: Bool      // タップしているか
    let isPlaying: Bool       // マップのタブを表示中か
    let photoCount: Int       // 開催中のイベントで撮られた写真の枚数
    let pinScale: CGFloat     // ズームに合わせた大きさ(1〜2)

    // 開催前で選ばれていないピンも動かすか
    // (false: 止めた絵で表示して軽くする。ピンが多いと Rive の描画が重くなるため)
    static let animateIdlePins = false

    var body: some View {
        let base = baseSize
        pinContent
            .frame(width: base, height: base)                    // Rive の描画面の大きさは固定
            .contentShape(Rectangle())
            .scaleEffect(pinScale, anchor: .bottom)              // 見た目だけ拡大(足元は動かさない)
            // タップできる範囲と置き場所だけ、拡大後の大きさに合わせる(中の Rive の大きさは変わらない)
            .frame(width: base * pinScale, height: base * pinScale, alignment: .bottom)
            // 足元がイベントの場所に来るように、下の空きの分だけ下にはみ出させる
            .padding(.bottom, -base * pinScale * emptyBottomRatio)
            .livePinEffect(isLive)
    }

    private var animates: Bool {
        Self.animateIdlePins || isLive || isSelected
    }

    @ViewBuilder
    private var pinContent: some View {
        switch pinStyle {
        case .pin2:
            // 新しいピン(pin2.riv)
            Pin2PinView(animates: animates, isSelected: isSelected, isPlaying: isPlaying)
        case .tintyan:
            // 旧ピン(ちんちゃん)
            TintyanPinView(values: tintyanValues,
                           usesRive: animates,
                           isSelected: isSelected,
                           eventID: eventID,
                           isPlaying: isPlaying)
        }
    }

    // ふだんの大きさ(pt)
    private var baseSize: CGFloat {
        switch pinStyle {
        case .pin2:    return Pin2View.baseSize
        case .tintyan: return 80
        }
    }

    // 枠の下のあき
    private var emptyBottomRatio: CGFloat {
        switch pinStyle {
        case .pin2:    return Pin2View.emptyBottomRatio
        case .tintyan: return TintyanView.emptyBottomRatio
        }
    }

    // ちんちゃんの数値(状況によって変える)
    private var tintyanValues: TintyanValues {
        if isLive {
            return .live(photoCount: photoCount, eventID: eventID)   // 開催中(撮られた写真の枚数で盛り上がる)
        } else if isSelected {
            return .selected      // 開催前で、タップしているとき
        } else {
            return .beforeStart   // 開催前(ふだん)
        }
    }
}
