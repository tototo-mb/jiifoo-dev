import SwiftUI

// アプリの起動ファイル
// ※ 新規プロジェクトで自動作成された「〇〇App.swift」の中身を、このファイルの内容に置き換えてください。
//    （このファイルを追加して元のファイルも残すと @main が2つになりエラーになります）
@main
struct EventMapApp: App {
    @State private var locationManager = LocationManager()
    @State private var eventStore = EventStore()

    var body: some Scene {
        WindowGroup {
            //SupabaseTestView()//テスト用
            MainTabView()
                .environment(locationManager)   // どの画面からでも使えるようにする
                .environment(eventStore)
            
        }
    }
}
