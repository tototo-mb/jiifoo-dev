
import UserNotifications



enum NotificationManager {


static func scheduleGathering(id: UUID,
                            title: String,
                            placeName: String,
                            startsAt: Date,
                            isDropIn: Bool = false) async {
    //通知の中身(途中参加OK型は「間も無く開始」)
    let content = UNMutableNotificationContent()
    if isDropIn {
        content.title = "まもなくイベントが開始されます"
        content.body = "参加予定のイベントがまもなく始まります。\nイベント名：\(title)\n会場：\(placeName)"
    } else {
        content.title = "集合モードが始まりました"
        content.body = "イベント名：\(title)\n会場：\(placeName)"
    }
    content.sound = .default

    //通知のトリガー
    let notifyAt = startsAt.addingTimeInterval(-5 * 60) // 開始5分前に通知
    let seconds = notifyAt.timeIntervalSinceNow //今から何秒後に開始？
    guard seconds > 0 else {return} // すでに開始時刻を過ぎていたら予約しない

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false) //一度だけ通知

    //通知の予約を作成する
    let request = UNNotificationRequest(
        identifier: id.uuidString, 
        content: content,
        trigger: trigger
    )
     try? await UNUserNotificationCenter.current().add(request)
     }


    static func scheduleGathering(for event: Event) async{
            //途中参加可能型も開始5分前に「まもなく開始」の通知を送る
            await scheduleGathering(id: event.id,
                                title: event.title,
                                placeName: event.placeName,
                                startsAt:event.startsAt,
                                isDropIn: event.joinType == .dropIn)
    }

        //参加登録したイベントが中止になった場合
    //予約を全部削除して渡されたイベントを予約し直す
    static func syncGathering(with events: [Event]) async{
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for event in events{
            await scheduleGathering(for: event)
        }
    }

    // 途中参加OK型の会場に入ったとき、すぐに知らせる
    // isFirst:初めて着いたとき true、一度出て戻ってきたとき false
    static func notifyArrival(title: String, isFirst: Bool) async {
        let content = UNMutableNotificationContent()
        content.title = isFirst ? "会場に到着しました" : "会場に戻りました"
        content.body = "「\(title)」に参加中です。カメラ機能が使用可能です"
        content.sound = .default

        // trigger を nil にすると、すぐに通知する
        let request = UNNotificationRequest(identifier: "arrival-\(UUID().uuidString)",
                                            content: content,
                                            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // 写真が出ている画面でスクリーンショットが撮られたときの注意
    static func notifyScreenshotWarning() async {
        let content = UNMutableNotificationContent()
        content.title = "スクリーンショットが撮影されました"
        content.body = "写っている人の気持ちを考えて、写真の保存や共有はひかえてください"
        content.sound = .default

        // 同じ名前にして、続けて撮られても通知が何個も並ばないようにする
        let request = UNNotificationRequest(identifier: "screenshot-warning",
                                            content: content,
                                            trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    //ログアウトした時用
    //予約を全部消す
    static func cancelAll(){
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    //予約した通知を取り消す
    static func cancelGathering(eventID:UUID){
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [eventID.uuidString]) 
    } 

    //通知の許可をリクエスト
    static func requestPermission() async{
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert,.sound,.badge])
    }
}

@Observable
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate{
    static let shared = NotificationDelegate()

    var tappedEventID: UUID?

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async ->UNNotificationPresentationOptions{
                                    [.banner, .sound, .list]
                                }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async{
                                    let identifier = response.notification.request.identifier
                                    tappedEventID = UUID(uuidString: identifier)
                                }
}
