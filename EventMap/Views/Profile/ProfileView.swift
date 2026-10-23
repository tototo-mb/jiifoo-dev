import SwiftUI



// ③ インスタ風マイページ
struct ProfileView: View {
    @Environment(EventStore.self) private var eventStore

    // 仮のユーザー情報（ログイン機能ができたら差し替え）
    private let myName = "ユーザー名"
    private let bio = "自己紹介テキスト"
    private let followerCount = 0

    enum ProfileTab: String, CaseIterable {
        case posted = "過去に参加したイベント"
        case joined = "参加予定"
    }

    @State private var selectedTab: ProfileTab = .posted
    @State private var selectedEvent: Event?
    @State private var showLogoutDialog=false

    private var postedEvents: [Event] {[]}

    private var gridEvents: [Event] {
        selectedTab == .posted ? postedEvents : eventStore.joinedEvents
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProfileHeaderView(name: myName,
                                      bio: bio,
                                      postedCount: postedEvents.count,
                                      joinedCount: eventStore.joinedEvents.count,
                                      followerCount: followerCount)

                    // 掲載 / 参加予定 の切り替え
                    Picker("表示", selection: $selectedTab) {
                        ForEach(ProfileTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // 3列のグリッド
                    if gridEvents.isEmpty {
                        ContentUnavailableView(
                            selectedTab == .posted ? "掲載したイベント" : "参加したイベントはありません",
                            systemImage: "calendar.badge.exclamationmark")
                            .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(gridEvents) { event in
                                Button {
                                    selectedEvent = event
                                } label: {
                                    EventGridTile(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top)
            }
            .navigationTitle(myName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // 設定画面
                        Button("ログアウト",systemImage: "rectangle.portrait.and.arrow.right",
                               role: .destructive){
                            showLogoutDialog=true
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                        
                    }
                }
            }
            .confirmationDialog("ログアウトしますか？", isPresented:$showLogoutDialog, titleVisibility:.visible){
                Button("ログアウト",role: .destructive){
                    Task{
                        try? await JiifooAPI.signOut()
                    }
                }
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event)
                    .environment(eventStore)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

// グリッドの1マス
struct EventGridTile: View {
    let event: Event

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(event.scale.color.gradient)
            Text(event.title)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(6)
        }
        .aspectRatio(1, contentMode: .fit)   // 正方形
    }
}

#Preview {
    ProfileView()
        .environment(EventStore())
}
