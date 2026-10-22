import SwiftUI

// イベント詳細画面（マップ・一覧・マイページ共通）
struct EventDetailView: View {
    let event: Event
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @State private var showCancelDialog = false

    private var isJoined: Bool { eventStore.isJoined(event) }
    private var isMine: Bool { eventStore.isMine(event) }
    private var distance: Double? { locationManager.distance(to: event.coordinate) }
    private var isJoinable: Bool { locationManager.isJoinable(event.coordinate) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("カテゴリ", value: event.category)
                    LabeledContent("開始") {
                        Text(event.startsAt, style: .time)
                    }
                    LabeledContent("参加者", value: "\(event.participantCount) / \(event.capacity)人")
                    LabeledContent("掲載者", value: event.scale.label)
                    LabeledContent("場所", value: event.placeName)
                    if let distance {
                        LabeledContent("現在地から", value: formatDistance(distance))
                    }
                }
                if !event.description.isEmpty {
                    Section("詳細") {
                        Text(event.description)
                    }
                }
            }            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            // 画面下に参加ボタンを固定
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    // 範囲外のときの説明
                    if !isJoined && !isJoinable && !isMine {
                        Text(outOfRangeMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if isJoined {
                            showCancelDialog = true
                        } else {
                            withAnimation { eventStore.join(event) }
                        }
                    } label: {
                        Label(buttonTitle, systemImage: buttonIcon)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isJoined ? .green : .blue)
                    // 参加済みならキャンセルはいつでもできる。未参加なら範囲内のときだけ押せる
                    .disabled(isMine || (!isJoined && (!isJoinable || event.isFull)))
                }
                .padding()
                .background(.bar)
            }
            .confirmationDialog("参加をキャンセルしますか？",
                                isPresented: $showCancelDialog,
                                titleVisibility: .visible) {
                Button("参加をキャンセル", role: .destructive) {
                    withAnimation { eventStore.cancel(event) }
                }
            }
            .sensoryFeedback(.success, trigger: isJoined)
            // 予約結果やエラーのお知らせ(シート表示中はこちらで出す)
            .alert(eventStore.message ?? "", isPresented: Binding(
                get: { eventStore.message != nil },
                set: { if !$0 { eventStore.message = nil } }
            )) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    // MARK: - 表示用

    private var buttonTitle: String {
        if isMine { return "あなたが主催中" }
        if isJoined { return "参加予定" }
        if event.isFull { return "満員です" }
        return isJoinable ? "参加する" : "範囲外のため参加できません"
    }

    private var buttonIcon: String {
        if isMine { return "flame.fill" }
        if isJoined { return "checkmark.circle.fill" }
        if event.isFull { return "person.3.fill" }
        return isJoinable ? "person.badge.plus" : "location.slash"
    }

    private var outOfRangeMessage: String {
        guard let distance else {
            return "現在地を取得できていません。位置情報の設定を確認してください"
        }
        let remaining = distance - LocationManager.joinableRadius
        return "参加できるのは現在地から\(Int(LocationManager.joinableRadius))m以内のイベントです（あと\(formatDistance(remaining))）"
    }
}

#Preview {
    EventDetailView(event: sampleEvents[0])
        .environment(EventStore(events: sampleEvents))
        .environment(LocationManager())
}
