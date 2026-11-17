import SwiftUI

// タブ関係
struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(EventStore.self) private var eventStore
    @State private var selectedTab = 0

    //アプリが戻ったら読み直しして法人審査状況を反映させる
    @Environment(\.scenePhase) private var scenePhase //アプリが前面にあるか



    var body: some View {
        TabView(selection: $selectedTab) {
            EventMapView()
                .tabItem {
                    Image(systemName: "map")
                    Text("イベントマップ")
                }
                .tag(0)
            
            if authManager.isCorporate{
                //
                // 作成に成功したらマップのタブへ切り替える
                CreateEventView(onCreated: { selectedTab = 0 })
                    .tabItem{
                        Image(systemName: "plus.circle")
                        Text("イベント作成")
                    }
                    .tag(1)
            }else{
                NearbyEventListView()
                    .tabItem{
                        Image(systemName: "magnifyingglass")
                        Text("イベント検索")
                    }
                    .tag(1)
            }
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("マイページ")
                }
                .tag(2)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        // 通知の許可をリクエスト
        .task{
            await NotificationManager.requestPermission()
        }
        .onChange(of: NotificationDelegate.shared.tappedEventID){_, eventID in
            if eventID != nil{
                selectedTab = 0
            }
        }
        .onChange(of: eventStore.focusedEvent?.id) {_, id in
            if id != nil {
                selectedTab = 0
            }
        }
        .onChange(of: scenePhase){_,phase in
            if phase == .active{
                Task{ await authManager.reloadOrganizations() }
                Task{ await eventStore.checkNotices() }
            }
        }
        // 起動したとき、参加していたイベントが中止・場所変更されていないか確認
        .task {
            await eventStore.checkNotices()
        }
        // 参加していたイベントの中止・集合場所変更のお知らせ
        .alert(eventStore.noticeTitle, isPresented: Binding(
            get: { eventStore.hasNotices },
            set: { if !$0 { eventStore.acknowledgeNotices() } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(eventStore.noticeMessage)
        }
    }
}

#Preview {
    MainTabView()
        .environment(LocationManager())
        .environment(EventStore())
        .environment(AuthManager())
}
