import SwiftUI
import MapKit
import Combine   // ObservableObject と @Published を使うため

// 地図の上の地点検索バー
// ・入力中に場所の候補を出し、選ぶと onSelect でその場所を返す
// ・地図の画面(EventMapView)では、選んだ場所を中心に「全国のイベント」の地図を開く

// MARK: - 地点検索のロジック(入力中に候補を出す)

@MainActor
final class PlaceSearchModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet { completer.queryFragment = query }
    }
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = FarEventsView.japanRegion   // 日本の場所が先に出るように
    }

    func clear() {
        query = ""
        results = []
    }

    // 候補 → 実際の場所(座標つき)に変換
    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first
    }

    // MKLocalSearchCompleterDelegate(メインスレッドで呼ばれる)
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            self.results = completer.results
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            self.results = []
        }
    }
}

// MARK: - 検索バー本体

struct PlaceSearchBar: View {
    @StateObject private var model = PlaceSearchModel()
    @FocusState private var focused: Bool

    // 場所が選ばれたとき
    var onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // 入力欄
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("全国のイベントはここから検索！！", text: $model.query)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let first = model.results.first { select(first) }
                    }

                if !model.query.isEmpty {
                    Button {
                        model.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("入力を消す")
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 50)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)

            // 候補リスト(入力中だけ表示)
            if focused && !model.results.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.results, id: \.self) { item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.body)
                                            .foregroundStyle(.primary)
                                        if !item.subtitle.isEmpty {
                                            Text(item.subtitle)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .frame(maxHeight: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ここに後でカテゴリのチップ列を追加する予定
        }
        .animation(.easeOut(duration: 0.2), value: focused && !model.results.isEmpty)
    }

    private func select(_ completion: MKLocalSearchCompletion) {
        focused = false
        Task {
            guard let item = await model.resolve(completion) else { return }
            model.clear()   // 選んだら入力は空に戻す(地図の画面に戻ったとき、きれいな状態にする)
            onSelect(item)
        }
    }
}

#Preview {
    Map()
        .overlay(alignment: .top) {
            PlaceSearchBar { _ in }
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
}
