import SwiftUI

// イベントマップの絞り込み画面（右下のフィルターボタンから開く）
struct EventFilterView: View {
    @Environment(EventStore.self) private var eventStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("参加中のイベントだけ", isOn: Bindable(eventStore).filter.onlyJoined)
                } footer: {
                    Text("参加予定のイベントと、自分が主催したイベントだけを地図に表示します。")
                }

                Section {
                    ForEach(JoinType.allCases, id: \.self) { type in
                        Toggle(type.label, isOn: binding(for: type))
                    }
                } header: {
                    Text("イベントタイプ")
                } footer: {
                    Text("オンにしたタイプのイベントだけ地図に表示します。")
                }

                // カテゴリはカテゴリ一覧が決まったらここに追加する
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("リセット") {
                        eventStore.filter = EventFilter()
                    }
                    .disabled(!eventStore.filter.isActive)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }

    // トグル1つ分のオン・オフを filter.joinTypes とつなぐ
    private func binding(for type: JoinType) -> Binding<Bool> {
        Binding(
            get: { eventStore.filter.joinTypes.contains(type) },
            set: { isOn in
                if isOn {
                    eventStore.filter.joinTypes.insert(type)
                } else {
                    eventStore.filter.joinTypes.remove(type)
                }
            }
        )
    }
}

#Preview {
    EventFilterView()
        .environment(EventStore(events: sampleEvents))
}
