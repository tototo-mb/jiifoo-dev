import Foundation

// イベントマップの絞り込み条件
// 何も外していない状態（全部表示）が初期値
struct EventFilter: Equatable {
    // 表示するイベントタイプ（時間厳守 / 途中参加OK）
    var joinTypes: Set<JoinType> = Set(JoinType.allCases)

    // 何か絞り込んでいるか（ボタンの見た目を変えるのに使う）
    var isActive: Bool {
        self != EventFilter()
    }

    // このイベントを表示するか
    func matches(_ event: Event) -> Bool {
        joinTypes.contains(event.joinType)
    }
}
