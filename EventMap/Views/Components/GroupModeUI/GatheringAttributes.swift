import ActivityKit
import Foundation

// 集合カウントダウンの Live Activity で使うデータ
// アプリ本体とウィジェットの両方で使う（Target Membership を両方チェック）
struct GatheringAttributes: ActivityAttributes {
    // 途中で変わる値
    struct ContentState: Codable, Hashable {
        var meetTime: Date          // 集合時刻
    }

    // 最初に決めたら変わらない値
    var eventTitle: String          // イベント名
}
