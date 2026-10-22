import SwiftUI

// アプリの起動ファイル
// ※ 新規プロジェクトで自動作成された「〇〇App.swift」の中身を、このファイルの内容に置き換えてください。
//    （このファイルを追加して元のファイルも残すと @main が2つになりエラーになります）
@main
struct EventMapApp: App {
    @State private var locationManager = LocationManager()
    @State private var eventStore = EventStore()
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            //SupabaseTestView()//テスト用
            Group{if authManager.isChecking == true{
                ProgressView()
            }else if  authManager.isLoggedIn == true{
                    MainTabView()
                        .environment(locationManager)
                        .environment(eventStore)
                        .environment(authManager)
                }else{
                    LoginView()
                }
            }
            .task {
                await authManager.startListening()
            }
        }
    }
}
