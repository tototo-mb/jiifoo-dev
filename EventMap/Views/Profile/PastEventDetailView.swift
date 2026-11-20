import SwiftUI

// 過去のイベントの詳細(マイページの「過去に参加したイベント」から開く)
// 到着時の写真を表示する
//   参加者 → 自分が撮った写真だけ
//   主催者 → 全員分
// ※ 誰の写真が見えるかは Supabase の Storage のルールで決まっている(ここは表示するだけ)
struct PastEventDetailView: View {
    let event: PastEvent

    @State private var photoUserIDs: [UUID] = []
    @State private var memberNames: [UUID: String] = [:]
    @State private var isLoading = true
    @State private var viewingUserID: UUID?
    @State private var memoryPaths: [String] = []      // 自分が撮った思い出の写真(古い順)
    @State private var viewingMemoryPath: String?      // 大きく表示している思い出の写真


    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        List {
            Section {
                LabeledContent("日時") {
                    Text(event.startsAt, format: .dateTime.year().month().day().hour().minute())
                }
                LabeledContent("場所", value: event.placeName)
                LabeledContent("立場", value: event.isCreator ? "主催" : "参加")
            }


            // 思い出の写真(自分だけが見られる)
            Section {
                if isLoading {
                    HStack { ProgressView(); Text("読み込み中…") }
                } else if memoryPaths.isEmpty {
                    Text("このイベントで撮影した写真はありません")
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(memoryPaths, id: \.self) { path in
                            Button {
                                viewingMemoryPath = path
                            } label: {
                                StoredPhotoView(path: path)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("思い出の写真")
            } footer: {
                Text("自分だけが見られます")
            }


            Section {
                if isLoading {
                    HStack { ProgressView(); Text("読み込み中…") }
                } else if photoUserIDs.isEmpty {
                    Text(event.isCreator ? "このイベントで撮られた写真はありません" : "このイベントで撮った写真はありません")
                        .foregroundStyle(.secondary)
                } else if !event.isCreator, let myPhotoID = photoUserIDs.first {
                    // 参加者: 自分の写真1枚を大きく表示
                    StoredPhotoView(path: PhotoStorage.arrivalPath(eventID: event.id, userID: myPhotoID),
                                    contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 320)
                        .listRowInsets(EdgeInsets())
                        .onTapGesture { viewingUserID = myPhotoID }
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(photoUserIDs, id: \.self) { userID in
                            Button {
                                viewingUserID = userID
                            } label: {
                                VStack(spacing: 4) {
                                    StoredPhotoView(path: PhotoStorage.arrivalPath(eventID: event.id, userID: userID))
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    // 主催者には誰の写真かを表示
                                    if event.isCreator {
                                        Text(memberNames[userID] ?? "参加者")
                                            .font(.caption2)
                                            .lineLimit(1)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(event.isCreator ? "参加者の写真" : "自分の写真")
            } footer: {
                Text(event.isCreator
                     ? "参加者が到着したときに撮った写真です"
                     : "到着したときに撮った写真です。主催者も見ることができます")
            }
        }
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        // 写真を大きく表示
        .sheet(item: Binding(
            get: { viewingUserID.map(IdentifiedUUID.init) },
            set: { viewingUserID = $0?.id }
        )) { item in
            NavigationStack {
                StoredPhotoView(path: PhotoStorage.arrivalPath(eventID: event.id, userID: item.id),
                                contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(event.isCreator ? (memberNames[item.id] ?? "参加者") : "自分の写真")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { viewingUserID = nil }
                        }
                    }
            }
        }
        // 思い出の写真を大きく表示
        .sheet(item: Binding(
            get: { viewingMemoryPath.map(IdentifiedPath.init) },
            set: { viewingMemoryPath = $0?.id }
        )) { item in
            NavigationStack {
                StoredPhotoView(path: item.id, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("思い出の写真")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("閉じる") { viewingMemoryPath = nil }
                        }
                    }
            }
        }

    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // 自分が撮った思い出の写真
        memoryPaths = (try? await JiifooAPI.myPhotoPaths(eventId: event.id)) ?? []
        // 見られる写真だけが返ってくる(参加者は自分の分、主催者は全員分)
        let ids = (try? await PhotoStorage.arrivalPhotoUserIDs(eventID: event.id)) ?? []
        photoUserIDs = ids.sorted { $0.uuidString < $1.uuidString }

        // 主催者には名前も出す(読み込めなければ「参加者」と表示)
        if event.isCreator, let members = try? await JiifooAPI.eventMembers(eventId: event.id) {
            memberNames = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0.displayName) })
        }
    }
}

// sheet(item:) で UUID を使うための入れ物
private struct IdentifiedUUID: Identifiable {
    let id: UUID
}

private struct IdentifiedPath: Identifiable {
    let id: String
}

#Preview {
    NavigationStack {
        PastEventDetailView(event: PastEvent(
            id: UUID(), title: "缶蹴り", placeName: "記念公園",
            startsAt: .now, kind: "corporate", isCreator: true))
    }
}
