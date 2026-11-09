
import UserNotifications

enum NotificationManager {


static func scheduleGathering(id: UUID,
                            title: String,
                            placeName: String,
                            startsAt: Date) async {
    //通知の中身
    let content = UNMutableNotificationContent()
    content.title = "集合モードが始まりました"
    content.body = "「\(title)」の集合場所：\(placeName)"
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
            await scheduleGathering(id: event.id,
                                title: event.title,
                                placeName: event.placeName,
                                startsAt:event.startsAt)
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
