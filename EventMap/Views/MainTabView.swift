import SwiftUI

// タブ関係
struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var selectedTab = 0

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
                CreateEventView(isTab: true)
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
    }
}

#Preview {
    MainTabView()
        .environment(LocationManager())
        .environment(EventStore())
        .environment(AuthManager())
}
