import SwiftUI
import UserNotifications

// アプリの起動ファイル
// ※ 新規プロジェクトで自動作成された「〇〇App.swift」の中身を、このファイルの内容に置き換えてください。
@main
struct EventMapApp: App {
    @State private var locationManager = LocationManager()
    @State private var eventStore = EventStore()
    @State private var authManager = AuthManager()
    @State private var gathering = GatheringMode()
    init(){
        //通知をアプリ使用中でも表示するための設定
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        // ピンのキャラクター(tintyan.riv)を、起動してすぐ裏で読み込んでおく
        // (地図にピンが出た瞬間に読み込むと、そこで固まることがあるため)
        Task.detached(priority: .userInitiated) {
            _ = TintyanRive.file
            _ = Pin2Rive.file
        }
    }
    
    
    
    var body: some Scene {
        WindowGroup {
            //SupabaseTestView()//テスト用
            Group{if authManager.isChecking == true{
                ProgressView()
            }else if  authManager.isLoggedIn == true && !authManager.isResettingPassword{
                MainTabView()
                    .environment(locationManager)
                    .environment(eventStore)
                    .environment(authManager)
                    .environment(gathering)
            }else{
                LoginView()
                    .environment(authManager)   // パスワード再設定で使う
            }
            }
            .task {
                await authManager.startListening()
            }
            .onChange(of: authManager.isLoggedIn){_,isLoggedIn in
                if !isLoggedIn{
                    eventStore.reset()
                }
            }
        }
    }
}
