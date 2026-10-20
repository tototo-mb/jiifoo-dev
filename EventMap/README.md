# EventMap ファイル構成

| ファイル | 機能 |
|---|---|
| `EventMapApp.swift` | 起動ファイル（自動作成された 〇〇App.swift の中身をこれに置き換える） |
| `Models/Event.swift` | イベントのデータ型・掲載ユーザーの種類（ピンの色） |
| `Models/SampleData.swift` | 仮のイベントデータ |
| `Models/EventStore.swift` | イベント一覧と参加状態の管理（後でバックエンドにつなぐ場所） |
| `Managers/LocationManager.swift` | 現在地の取得・距離の計算 |
| `Views/MainTabView.swift` | タブ（マップ / 検索 / マイページ） |
| `Views/Map/EventMapView.swift` | ① 地図・色分けピン・右下の現在地ボタン |
| `Views/Nearby/NearbyEventListView.swift` | ② 付近のイベント一覧（近い順・検索） |
| `Views/Nearby/EventRow.swift` | ② 一覧の1件分のカード |
| `Views/Profile/ProfileView.swift` | ③ マイページ（掲載 / 参加予定のグリッド） |
| `Views/Profile/ProfileHeaderView.swift` | ③ アイコン・数字・自己紹介 |
| `Views/Event/EventDetailView.swift` | 詳細＋参加ボタン（①②③共通） |
| `Views/Common/AnotherView.swift` | 未作成画面の仮置き |

## 新規プロジェクトへの入れ方

1. Xcode で iOS App（SwiftUI / Swift）を新規作成し、Minimum Deployments を iOS 17.0 以上にする
2. 自動作成された `ContentView.swift` を削除
3. 自動作成された `〇〇App.swift` の中身を `EventMapApp.swift` の内容に置き換える
4. `Models` `Managers` `Views` フォルダを Xcode にドラッグ（Copy items if needed にチェック）
5. Info タブに `Privacy - Location When In Use Usage Description` を追加
6. Command + B でビルド
