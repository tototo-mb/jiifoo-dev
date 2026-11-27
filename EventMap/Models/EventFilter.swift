import Foundation

// イベントマップの絞り込み条件
// 何も外していない状態（全部表示）が初期値
struct EventFilter: Equatable {
    // 表示するイベントタイプ（時間厳守 / 途中参加OK）
    var joinTypes: Set<JoinType> = Set(JoinType.allCases)

    // 参加中のイベントだけ表示する（自分が主催したイベントも含む）
    var onlyJoined = false

    // 何か絞り込んでいるか（ボタンの見た目を変えるのに使う）
    var isActive: Bool {
        self != EventFilter()
    }

    // このイベントを表示するか
    // joinedEventIDs: 自分が参加中(主催を含む)のイベントのID
    func matches(_ event: Event, joinedEventIDs: Set<Event.ID>) -> Bool {
        guard joinTypes.contains(event.joinType) else { return false }
        if onlyJoined && !joinedEventIDs.contains(event.id) { return false }
        return true
    }
}
