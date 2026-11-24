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
    @State private var showSettings=false

    @State private var pastEvents: [PastEvent] = []   // 過去に参加・主催したイベント(Supabase から読み込む)

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    private let stampColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProfileHeaderView(name: myName,
                                      bio: bio,
                                      postedCount: pastEvents.count,
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
                    switch selectedTab {
                    case .posted:
                        // 過去のイベント(タップで写真が見られる詳細へ)
                        if pastEvents.isEmpty {
                            ContentUnavailableView(
                                "過去に参加したイベントはありません",
                                systemImage: "calendar.badge.exclamationmark")
                                .padding(.top, 24)
                        } else {
                            // 参加スタンプを2列で並べる（タップで大きいスタンプと写真の画面へ）
                            LazyVGrid(columns: stampColumns, spacing: 12) {
                                ForEach(pastEvents) { event in
                                    NavigationLink(value: event) {
                                        StampOnPaper(stamp: ParticipationStamp(event: event), padding: 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    case .joined:
                        if eventStore.joinedEvents.isEmpty {
                            ContentUnavailableView(
                                "参加予定のイベントはありません",
                                systemImage: "calendar.badge.exclamationmark")
                                .padding(.top, 24)
                        } else {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(eventStore.joinedEvents) { event in
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
                }
                .padding(.top)
            }
            .navigationTitle(myName)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PastEvent.self) { event in
                PastEventDetailView(event: event)
            }
            // 表示するたびに過去のイベントを読み直す(引っ張って更新もできる)
            .task { await loadPastEvents() }
            .refreshable { await loadPastEvents() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button{
                        showSettings=true
                    }label:{
                        Image(systemName: "gearshape")
                    }
                }
            }
                    .sheet(isPresented :$showSettings) { SettingsView()
            }
        }
        .sheet(item: $selectedEvent){
            event in EventDetailView(event: event)
                .environment(eventStore)
                .presentationDetents([.medium,.large])
        }
    }
}

extension ProfileView {
    private func loadPastEvents() async {
        if let list = try? await JiifooAPI.myPastEvents() {
            pastEvents = list
        }
    }
}

// 過去のイベントのグリッドの1マス
struct PastEventGridTile: View {
    let event: PastEvent

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill((event.kind == "corporate" ? EventScale.businessMode : EventScale.privateMode).color.gradient)
                .opacity(0.8)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.caption.bold())
                    .lineLimit(2)
                Text(event.startsAt, format: .dateTime.month().day())
                    .font(.caption2)
            }
            .foregroundStyle(.white)
            .padding(6)
        }
        .overlay(alignment: .topTrailing) {
            if event.isCreator {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fit)   // 正方形
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
