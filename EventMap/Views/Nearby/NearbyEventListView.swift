import SwiftUI

//イベント検索を範囲で絞りこむ
enum SearchRange: String,CaseIterable,Identifiable {
    case near = "800m圏内"
    case wide = "10km圏内"
    case notionwide = "全範囲表示"

    var id: Self { self }

    //サーバーに送る範囲
    var radiusM: Double? {
        switch self {
        case .near: return 800
        case .wide: return 10_000
        case .notionwide: return nil
        }
    }
}

// ② 付近のイベントをスクロールで見る画面
struct NearbyEventListView: View {
    @Environment(LocationManager.self) private var locationManager
    @Environment(EventStore.self) private var eventStore

    @State private var searchText = ""
    @State private var selectedEvent: Event?
    @State private var range: SearchRange = .near //イベント検索で表示する初期範囲は800m
    @State private var events: [Event] = []
    @State private var isLoading = false

    //範囲が変わった時・現在地が変わったときに読み直す
    private var loadKey: String {
        "\(range.rawValue)-\(locationManager.userLocation != nil)"
    }

    // 検索で絞り込み → 現在地から近い順に並べる
    private var displayedEvents: [Event] {
        let filtered = events.filter { event in
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
                    Picker("範囲",selection: $range) {
                        ForEach(SearchRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
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

                    if isLoading {
                        ProgressView()
                            .padding(.top,40)
                    } else if displayedEvents.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("付近のイベント")
            .searchable(text: $searchText, prompt: "イベント名・場所で検索")
            //範囲が変わった時、現在地が変わった時に読み込む
            .task(id: loadKey) {
                await loadEvents()
            }
            // 下に引っ張ると読み直す
            .refreshable {
                await Task{ await loadEvents() }.value
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailView(event: event, showMapButton: true)
                    .environment(eventStore)
                    .presentationDetents([.medium, .large])
            }
        }
    }
        private func loadEvents() async {
            guard let here = locationManager.userLocation else { return }
            isLoading = true
            defer { isLoading = false }
            do {
                let pins = (try await JiifooAPI.searchEvents(
                    latitude: here.latitude,
                    longitude: here.longitude,
                    radiusM: range.radiusM)) 
                events = pins.map(Event.init(pin:))
            } catch {
                print("イベント検索に失敗しました：",error)
            }
        }
}

#Preview {
    NearbyEventListView()
        .environment(LocationManager())
        .environment(EventStore())
}
