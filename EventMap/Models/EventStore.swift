import SwiftUI
import Observation

// イベントと参加状態をアプリ全体で管理するクラス
// （後でバックエンドとつなぐときは、このクラスの中身を差し替えます）
@MainActor
@Observable
final class EventStore {
    var events: [Event] = sampleEvents
    var joinedEventIDs: Set<Event.ID> = []   // 参加予定のイベント

    func isJoined(_ event: Event) -> Bool {
        joinedEventIDs.contains(event.id)
    }

    func join(_ event: Event) {
        joinedEventIDs.insert(event.id)
    }

    func cancel(_ event: Event) {
        joinedEventIDs.remove(event.id)
    }

    // 参加予定のイベント一覧（マイページで使用）
    var joinedEvents: [Event] {
        events.filter { joinedEventIDs.contains($0.id) }
    }

    // 指定したユーザーが掲載したイベント一覧（マイページで使用）
    func events(postedBy creatorID:UUID) -> [Event] {
        events.filter { $0.creatorID == creatorID }
    }
}
