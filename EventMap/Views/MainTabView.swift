import SwiftUI

// タブ関係
struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(EventStore.self) private var eventStore
    @State private var selectedTab = 0
    @State private var createHasInput = false   // イベント作成タブに入力途中のものがあるか
    @State private var createLeaveTo: Int?      // 作成タブから移ろうとしているタブ(下書きをどうするか聞いている間)
    @State private var isKeyboardShown = false  // キーボードが出ているか(出ている間は下のボタンを隠す)

    //アプリが戻ったら読み直しして法人審査状況を反映させる
    @Environment(\.scenePhase) private var scenePhase //アプリが前面にあるか



    var body: some View {
        TabView(selection: Binding(
            get: { selectedTab },
            set: { selectTab($0) })) {
            // 下の横長のバーは隠す(代わりに、下に浮かべたボタンで切り替える)
            EventMapView(isActive: selectedTab == 0)
                .toolbar(.hidden, for: .tabBar)
                .tabButtonsSpace()
                .tag(0)

            if authManager.isCorporate {
                // 作成に成功したらマップのタブへ切り替える
                CreateEventView(onCreated: { selectedTab = 0 },
                                hasInput: $createHasInput,
                                leaveTo: $createLeaveTo,
                                onLeave: { tab in selectedTab = tab })
                    .toolbar(.hidden, for: .tabBar)
                    .tabButtonsSpace()
                    .tag(1)
            }

            ProfileView()
                .toolbar(.hidden, for: .tabBar)
                .tabButtonsSpace()
                .tag(2)
        }
        // 画面の下に、独立したタブのボタンを浮かべる
        // (各画面は tabButtonsSpace() でこの分の下をあけてあるので、重ならない)
        .overlay(alignment: .bottom) {
            // キーボードが出ている間は隠す(キーボードの「閉じる」や入力欄と重ならないように)
            if isKeyboardShown {
                keyboardCloseBar
            } else {
                tabButtons
            }
        }
        // キーボードが出た・閉じたを知る
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardShown = false
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


    // タブを切り替える(入力途中で作成タブから離れるときは、先に下書きをどうするか聞く)
    private func selectTab(_ newTab: Int) {
        if authManager.isCorporate && selectedTab == 1 && newTab != 1 && createHasInput {
            createLeaveTo = newTab
        } else {
            selectedTab = newTab
        }
    }

    // 下に並べるボタン(法人は「イベント作成」も出す)
    private var tabButtons: some View {
        HStack(spacing: 12) {
            tabButton(tab: 0, icon: "map", selectedIcon: "map.fill", label: "イベントマップ")
            if authManager.isCorporate {
                tabButton(tab: 1, icon: "plus", selectedIcon: "plus", label: "イベント作成")
            }
            tabButton(tab: 2, icon: "person", selectedIcon: "person.fill", label: "マイページ")
        }
        .padding(.bottom, 4)
    } 
    // キーボードが出ている間、下のボタンの代わりに出す「閉じる」
    private var keyboardCloseBar: some View {
        HStack {
            Spacer()
            Button("閉じる") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 3)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
     // ボタン1つ分(選んでいるタブは、塗りつぶしのアイコン・濃い色)
    private func tabButton(tab: Int, icon: String, selectedIcon: String, label: String) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectTab(tab)
        } label: {
            Image(systemName: isSelected ? selectedIcon : icon)
                .font(.title3.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(width: 56, height: 56)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// 下に浮かべたタブのボタンの分だけ、画面の下をあける
// (地図の右下のボタンや「到着しました」、作成画面の一番下などが、タブのボタンに隠れないように)
private extension View {
    func tabButtonsSpace() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 64)   // ボタンの高さ 56 ＋ すき間
        }
    }
}


#Preview {
    MainTabView()
        .environment(LocationManager())
        .environment(EventStore())
        .environment(AuthManager())
        .environment(GatheringMode())
}
