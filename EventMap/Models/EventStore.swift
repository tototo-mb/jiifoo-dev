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
    var checkedInEventIDs: Set<Event.ID> = [] //参加済み（会場に到着済み）のイベント

    @ObservationIgnored private var isInVenue: [Event.ID: Bool] = [:] //途中参加OK型の会場の中にいるか(出入りの通知用)
    var arrivalEffectEvent: Event? //会場に初めて着いたときの演出を出しているイベント

    @ObservationIgnored private var arrivingIDs: Set<Event.ID> = [] //一度だけ、現在"check_in"を送っている途中のイベント取り出す
    var isLoading = false
    var message: String?                      // 画面に出すお知らせ・エラー
    var focusedEvent: Event?
    var filter = EventFilter()                // 地図の絞り込み条件
    var cancelledNotices: [CancelledEvent] = [] // 参加していて中止されたイベント(お知らせ用)
    var placeChangedNotices: [PlaceChangedEvent] = [] // 参加していて集合場所が変わったイベント(お知らせ用)

    // 絞り込み条件に合うイベント（地図に表示する分）
    var filteredEvents: [Event] {
        events.filter(filter.matches)
    }


    
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
            async let checkedIn = JiifooAPI.myCheckedInEventIDs()
            let serverEvents=try await pins.map(Event.init(pin: ))
            events=serverEvents + (Self.showSampleEvents ? sampleEvents :[])
            joinedEventIDs = try await joined
            checkedInEventIDs = try await checkedIn
            await NotificationManager.syncGathering(with: joinedEvents)
            await GatheringActivityManager.sync(with: joinedEvents) //デバイスがロック状態時sのカウントダウン
        } catch {
            message = "イベントを読み込めませんでした"
            print("イベントの読み込みに失敗:", error)
        }
    }

    // 予約・キャンセル後や集合モード終了時に、今の場所でもう一度読み込む
    func reload() async {
        guard let center = lastLoadedCenter?.coordinate else { return }
        await load(near: center, force: true)
    }

    // MARK: - 参加状態

    func isJoined(_ event: Event) -> Bool {
        joinedEventIDs.contains(event.id)
    }

    func isCheckedIn(_ event: Event) -> Bool {
        checkedInEventIDs.contains(event.id)
    }

    // 会場の広さ(サーバーの check_in と同じ)と、「会場を出た」とみなす距離
    // (GPS は止まっていても数十m ぶれるので、出たかどうかは少し遠めで判断する)
    static let venueRadius: Double = 100
    static let venueLeaveRadius: Double = 150

    //途中参加可能型：参加予定のイベントの会場(100m以内)に着いたら、自動的に参加済みにする
    // 1回目(参加済になったとき):通知 + 光・振動
    // 2回目以降(一度出て、また入ったとき):通知だけ
    func arriveIfNear(_ here: CLLocationCoordinate2D) {
        let now = Date()
        let hereLocation = CLLocation(latitude: here.latitude, longitude: here.longitude)
        for event in events {
            //途中参加可能型で、イベント開催中で、参加予定のイベントだけ
            guard event.joinType == .dropIn,
                  isJoined(event),
                  event.startsAt <= now, now < event.endsAt else { continue }
            let venue = CLLocation(latitude: event.latitude, longitude: event.longitude)
            let distance = hereLocation.distance(from: venue)

            // 2回目以降:会場を出入りしたか調べる
            if isCheckedIn(event) {
                updateVenueState(event, distance: distance)
                continue
            }

            // 1回目:イベント開催地から100m以内に入ったら参加済にする
            guard !arrivingIDs.contains(event.id),
                  distance <= Self.venueRadius else { continue }

            arrivingIDs.insert(event.id)
            Task{
                let result = ( try? await JiifooAPI.checkIn(
                    eventId: event.id, latitude: here.latitude, longitude: here.longitude)) ?? "error"
                if result == "ok" || result == "already_checked_in" {
                    checkedInEventIDs.insert(event.id)
                }
                // 初めて参加済になったときだけ、通知と演出
                if result == "ok" {
                    isInVenue[event.id] = true
                    arrivalEffectEvent = event
                    await NotificationManager.notifyArrival(title: event.title, isFirst: true)
                }
                arrivingIDs.remove(event.id)
            }
        }
    }

    // 会場を出入りしたか調べて、入ったときは通知する(参加済のイベント用)
    // ・100m 以内 → 「中」。前が「外」なら通知
    // ・150m より遠い → 「外」
    // ・その間 → 前の状態のまま(境目でぶれても何度も通知しない)
    private func updateVenueState(_ event: Event, distance: Double) {
        let wasInside = isInVenue[event.id]   // nil = まだわからない(アプリを開いた直後など)
        if distance <= Self.venueRadius {
            if wasInside == false {
                Task { await NotificationManager.notifyArrival(title: event.title, isFirst: false) }
            }
            isInVenue[event.id] = true
        } else if distance > Self.venueLeaveRadius {
            isInVenue[event.id] = false
        }
    }


    func isMine(_ event: Event) -> Bool {
        guard let myUserID, let creator = event.creatorID else { return false }
        return creator == myUserID
    }

    // 同じ時間帯(開始時刻の差が1時間未満)に、すでに主催・参加しているイベント
    // ※最終的な判定は Supabase の reserve_event が行う(ここは見た目のため)
    func conflictingEvent(for event: Event) -> Event? {
        guard event.joinType == .fixed else { return nil } //追加
        return events.first { other in
            other.id != event.id
                && other.joinType == .fixed //追加
                && joinedEventIDs.contains(other.id)
                && abs(other.startsAt.timeIntervalSince(event.startsAt)) < 60 * 60
        }
    }

    // 参加する(画面からはこれを呼ぶだけでよい)
    func join(_ event: Event) {
        Task {
            do {
                let result = try await JiifooAPI.reserve(eventId: event.id)
                switch result {
                case "ok":
                    joinedEventIDs.insert(event.id)
                    await NotificationManager.scheduleGathering(for: event)
                case "already_reserved":
                    joinedEventIDs.insert(event.id)
                    await NotificationManager.scheduleGathering(for: event)
                case "full":
                    message = "満員のため参加できませんでした"
                case "closed":
                    message = "募集が終了しました"
                case "time_conflict":
                    message = "同じ時間帯に参加予定のイベントがあるため参加できません"
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
                    NotificationManager.cancelGathering(eventID: event.id)
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

    func cancelEvent(_ event: Event) {
        Task{
            do{
                let result = try await JiifooAPI.cancelEvent(eventId: event.id)
                switch result {
                    case "ok","already_cancelled":
                        //自分のデバイスに保存している通知も取り消し
                        NotificationManager.cancelGathering(eventID: event.id)
                    case "already_started":
                        message = "開始したイベントは中止できません"
                    case "not_allowed":
                        message = "イベント主催者だけがキャンセルできます"
                    default:
                        message = "中止できませんでした(\(result))"
                }
            } catch {
                message = "通信エラー：イベント中止できませんでした"
            }
            await reload()
        }
    }

    // MARK: - 参加者へのお知らせ(中止・集合場所の変更)

    // お知らせがあるか(MainTabView のアラート表示に使う)
    var hasNotices: Bool {
        !cancelledNotices.isEmpty || !placeChangedNotices.isEmpty
    }

    // 参加していたイベントが中止・場所変更されていないか確認する(アプリを開いたときに呼ぶ)
    // 中止のときの予約の取り消しは Supabase の cancel_event が済ませているので、ここでは知らせるだけ
    func checkNotices() async {
        async let cancelled = try? JiifooAPI.myCancelledEvents()
        async let changed = try? JiifooAPI.myPlaceChangedEvents()
        let cancelledList = await cancelled ?? []
        let changedList = await changed ?? []

        for event in cancelledList {
            joinedEventIDs.remove(event.id)
            NotificationManager.cancelGathering(eventID: event.id)  // このiPhoneの集合通知も消す
        }
        if !cancelledList.isEmpty { cancelledNotices = cancelledList }
        if !changedList.isEmpty {
            placeChangedNotices = changedList
            await reload()   // 地図と集合通知を新しい場所に合わせる
        }
    }

    // お知らせを閉じたとき：知らせ済みにして、次から出さない
    func acknowledgeNotices() {
        let cancelledIDs = cancelledNotices.map(\.id)
        let changedIDs = placeChangedNotices.map(\.id)
        cancelledNotices = []
        placeChangedNotices = []
        Task {
            do {
                if !cancelledIDs.isEmpty { try await JiifooAPI.markCancelNotified(eventIds: cancelledIDs) }
                if !changedIDs.isEmpty { try await JiifooAPI.markPlaceChangeSeen(eventIds: changedIDs) }
            } catch {
                print("お知らせを既読にできませんでした:", error)  // 次に開いたときにもう一度出る
            }
        }
    }

    // アラートのタイトル
    var noticeTitle: String {
        switch (cancelledNotices.isEmpty, placeChangedNotices.isEmpty) {
        case (false, true): return "イベントが中止されました"
        case (true, false): return "集合場所が変更されました"
        default:            return "参加予定のイベントのお知らせ"
        }
    }

    // アラートの本文
    var noticeMessage: String {
        var lines: [String] = []
        if !cancelledNotices.isEmpty {
            let titles = cancelledNotices.map { "「\($0.title)」" }.joined(separator: "\n")
            lines.append("\(titles)\nは主催者により中止されました。参加は取り消されています。")
        }
        for event in placeChangedNotices {
            lines.append("「\(event.title)」の集合場所が「\(event.placeName)」に変更されました。")
        }
        return lines.joined(separator: "\n\n")
    }

    // MARK: - イベント編集(主催者用)

    // 編集できるか(自分が主催していて、集合モードが始まる＝開始5分前より前)
    // ※最終的な判定は Supabase の update_event が行う
    func canEdit(_ event: Event) -> Bool {
        isMine(event) && Date.now < event.startsAt.addingTimeInterval(-5 * 60)
    }

    // イベントを編集する。成功なら nil、失敗ならエラーの文章を返す
    func update(
        _ event: Event,
        title: String,
        description: String,
        placeName: String,
        coordinate: CLLocationCoordinate2D
    ) async -> String? {
        do {
            let result = try await JiifooAPI.updateEvent(
                eventId: event.id,
                title: title,
                description: description,
                placeName: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
            switch result {
            case "ok":
                // 自分の集合通知も新しい名前・場所で予約し直す
                if event.joinType == .fixed {
                    NotificationManager.cancelGathering(eventID: event.id)
                    await NotificationManager.scheduleGathering(id: event.id,
                                                               title: title,
                                                               placeName: placeName,
                                                               startsAt: event.startsAt)
                }
                await reload()
                return nil
            case "too_late":
                return "集合モードが始まったため編集できません"
            case "not_editable":
                return "募集中のイベントだけ編集できます"
            case "not_allowed":
                return "イベント主催者だけが編集できます"
            case "invalid":
                return "イベント名と集合場所を正しく入力してください"
            default:
                return "編集できませんでした(\(result))"
            }
        } catch {
            print("イベント編集に失敗:", error)
            return "通信エラーで編集できませんでした"
        }
    }

    //イベント終了(途中参加可能型の主催者用)
    func end(_ event: Event){
        Task{
            do{
                let result = try await JiifooAPI.endEvent(eventId: event.id)
                switch result{
                case "ok":
                    break //成功：リロードしたら消える
                case "not_started":
                    message = "開始前のイベント終了はできません" //ここ変える、開始前でも中止できるようにする
                case "already_finished":
                    message = "このイベントはすでに終了しています"
                case "not_allowed":
                    message = "イベント主催者のみ終了できます"
                default:
                    message = "終了できませんでした(\(result))"
                }
            }catch{
                message = "通信エラーで終了できませんでした"
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
        capacity: Int?,
        organizationId:UUID?,
        joinType: JoinType,
        endsAt: Date?,
        photoEndsAt: Date?

    ) async -> Bool {
        do {
            //Supabaseにイベントを送る
            let newID = try await JiifooAPI.createEvent(
                title: title,
                category: category,
                description: description,
                placeName: placeName,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                startsAt: startsAt,
                capacity: capacity,
                organizationId: organizationId,
                // 11/13追加分
                joinType: joinType,
                endsAt: endsAt,
                photoEndsAt: photoEndsAt
            )
            //主催者にも集合モードの通知を予約
            if joinType == .fixed{
                await NotificationManager.scheduleGathering(id: newID,
                title: title,
                placeName: placeName,
                startsAt: startsAt
                )
            }
            // ② 地図を読み込み直す
            await reload()
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

    // 次に集合モードが始まる時刻(参加予定の時間厳守型イベントのうち、一番早いもの)
    var nextGatheringStart: Date? {
        joinedEvents
            .filter { $0.joinType == .fixed }
            .map { $0.startsAt.addingTimeInterval(-5 * 60) }
            .filter { $0 > .now }
            .min()
    }


    func reset(){
        events=[]
        joinedEventIDs = []
        myUserID = nil
        message = nil
        arrivalEffectEvent = nil
        isInVenue = [:]
        cancelledNotices = []
        placeChangedNotices = []
        lastLoadedCenter = nil
        //ログアウトしたとき、予約していた通知を全部消す
        NotificationManager.cancelAll()
        Task { await GatheringActivityManager.end()} //ログアウト後のしたらロック画面に表示しているカウントダウンも削除
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

 
