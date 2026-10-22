import SwiftUI

// ② 付近のイベントをスクロールで見る画面
struct NearbyEventListView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore

    @State private var searchText = ""
    @State private var selectedEvent: Event?

    // 検索で絞り込み → 現在地から近い順に並べる
    private var displayedEvents: [Event] {
        let filtered = eventStore.events.filter { event in
            searchText.isEmpty
            || event.title.contains(searchText)
            || event.placeName.contains(searchText)
            || event.description.contains(searchText)
        }
        return filtered.sorted { a, b in
            let da = locationManager.distance(to: a.coordinate) ?? .greatestFiniteMagnitude
            let db = locationManager.distance(to: b.coordinate) ?? .greatestFiniteMagnitude
            return da < db
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(displayedEvents) { event in
                        Button {
                            selectedEvent = event
                        } label: {
                            EventRow(event: event,
                                     distance: locationManager.distance(to: event.coordinate),
                                     isJoined: eventStore.isJoined(event))
                        }
                        .buttonStyle(.plain)
                    }

                    if displayedEvents.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("付近のイベント")
            .searchable(text: $searchText, prompt: "イベント名・場所で検索")
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event)
                    .environment(eventStore)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    NearbyEventListView()
        .environment(LocationManager())
        .environment(EventStore())
}
