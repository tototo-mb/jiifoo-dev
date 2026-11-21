import Foundation

// 写真まわりの注意喚起(文章と、一度見たかどうかの記録)
enum PhotoNotice {

    // MARK: - カメラを開く前(イベントごとに1回)

    static let cameraTitle = "撮影の前に"
    static let cameraMessage = """
    ・周りの安全や通行の妨げにならないようご注意ください。
    ・顔や名札、車のナンバーなど、個人がわかるものが写り込まないように気をつけてください。
    ・撮影禁止とされているエリアでの撮影はお控えください。
    """

    // 注意を見たイベントのID一覧を、この端末に覚えておく名前
    private static let seenKey = "cameraNoticeSeenEventIDs"

    // このイベントで、もう注意を見たか
    static func hasSeenCameraNotice(eventID: UUID) -> Bool {
        let ids = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        return ids.contains(eventID.uuidString)
    }

    // このイベントで注意を見た、と覚える
    static func markCameraNoticeSeen(eventID: UUID) {
        var ids = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        guard !ids.contains(eventID.uuidString) else { return }
        ids.append(eventID.uuidString)
        UserDefaults.standard.set(ids, forKey: seenKey)
    }

    // MARK: - 主催者が参加者の写真を見る前(毎回)

    static let organizerTitle = "参加者の写真を見る前に"
    static let organizerMessage = """
    ・写真は、参加の確認のためだけに使ってください
    ・参加者の許可なく、SNSなどに投稿・共有しないでください
    """
}