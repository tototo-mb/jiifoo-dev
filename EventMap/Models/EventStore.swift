import SwiftUI
import CoreLocation
import Observation

// イベントと参加状態をアプリ全体で管理するクラス
// データは Supabase(JiifooAPI)から読み込む
@MainActor
@Observable
final class EventStore {
    var events: [Event] = []
    var joinedEventIDs: Set<Event.ID> = []   // 参加予定(自分が作成したものも含む)
    var myUserID: UUID?

    var isLoading = false
    var message: String?                      // 画面に出すお知らせ・エラー


    
    //完成までサンプルデータ表示
    static let showSampleEvents=false
    
    // 最後に読み込んだ場所(少し動いただけでは読み直さないため)
    @ObservationIgnored private var lastLoadedCenter: CLLocation?

    init(events: [Event] = []) {
        self.events = events
    }
    

    // MARK: - 読み込み

    // 指定した場所の近くの募集中イベントを読み込む
    // force が false のときは、前回の場所から 300m 以上動いた場合だけ読み直す
    func load(near center: CLLocationCoordinate2D, force: Bool = false) async {
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        if !force, let last = lastLoadedCenter, last.distance(from: location) < 300 { return }
        lastLoadedCenter = location

        isLoading = true
        defer { isLoading = false }
        do {
            myUserID = await JiifooAPI.currentUserID()
            async let pins = JiifooAPI.nearbyEvents(latitude: center.latitude, longitude: center.longitude)
            async let joined = JiifooAPI.myActiveEventIDs()
            let serverEvents=try await pins.map(Event.init(pin: ))
            events=serverEvents + (Self.showSampleEvents ? sampleEvents :[])
            joinedEventIDs = try await joined
        } catch {
            message = "イベントを読み込めませんでした"
            print("イベントの読み込みに失敗:", error)
        }
    }

    // 予約・キャンセル後に、今の場所でもう一度読み込む
    private func reload() async {
        guard let center = lastLoadedCenter?.coordinate else { return }
        await load(near: center, force: true)
    }

    // MARK: - 参加状態

    func isJoined(_ event: Event) -> Bool {
        joinedEventIDs.contains(event.id)
    }

    func isMine(_ event: Event) -> Bool {
        guard let myUserID, let creator = event.creatorID else { return false }
        return creator == myUserID
    }

    // 参加する(画面からはこれを呼ぶだけでよい)
    func join(_ event: Event) {
        Task {
            do {
                let result = try await JiifooAPI.reserve(eventId: event.id)
                switch result {
                case "ok":
                    joinedEventIDs.insert(event.id)
                case "already_reserved":
                    joinedEventIDs.insert(event.id)
                case "full":
                    message = "満員のため参加できませんでした"
                case "closed":
                    message = "募集が終了しました"
                case "not_logged_in":
                    message = "ログインしてください"
                default:
                    message = "参加できませんでした(\(result))"
                }
            } catch {
                message = "通信エラーで参加できませんでした"
                print("予約に失敗:", error)
            }
            await reload()
        }
    }

    // 参加をキャンセルする
    func cancel(_ event: Event) {
        Task {
            do {
                let result = try await JiifooAPI.cancel(eventId: event.id)
                switch result {
                case "ok", "not_reserved":
                    joinedEventIDs.remove(event.id)
                case "too_late":
                    message = "集合モードに入ったためキャンセルできません"
                case "creator_cannot_cancel":
                    message = "主催者は参加をキャンセルできません"
                default:
                    message = "キャンセルできませんでした(\(result))"
                }
            } catch {
                message = "通信エラーでキャンセルできませんでした"
                print("キャンセルに失敗:", error)
            }
            await reload()
        }
    }
    
    //イベントを作る
    func create(
        title: String,
        category: String,
        description: String,
        placeName: String,
        coordinate: CLLocationCoordinate2D,
        startsAt: Date,
        capacity: Int
    ) async -> Bool {
        do {
            //Supabaseにイベントを送る
            _ = try await JiifooAPI.createEvent(
                title: title,
                category: category,
                description: description,
                placeName: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                startsAt: startsAt,
                capacity: capacity
            )
            // ② 地図を読み込み直す
            await load(near: coordinate,force: true)
            // ③ 成功を返す
            return true
        } catch {
            // ④ エラーのメッセージを入れる
            message="イベント作成に失敗しました"
            print("イベント作成に失敗：",error)
            // ⑤ 失敗を返す
            return false
        }
    }

    // MARK: - 一覧(マイページで使用)

    // 参加予定のイベント一覧
    // ※今は「読み込んだ範囲(近く)」のイベントだけが対象
    var joinedEvents: [Event] {
        events.filter { joinedEventIDs.contains($0.id) }
    }

    // 指定したユーザーが掲載したイベント一覧
    func events(postedBy creatorID: UUID) -> [Event] {
        events.filter { $0.creatorID == creatorID }
    }
}
