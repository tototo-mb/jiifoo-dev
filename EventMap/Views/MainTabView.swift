import SwiftUI

// タブ関係
struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            EventMapView()
                .tabItem {
                    Image(systemName: "map")
                    Text("イベントマップ")
                }
                .tag(0)
            NearbyEventListView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("イベント検索")
                }
                .tag(1)
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
}
