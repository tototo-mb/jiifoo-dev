import SwiftUI

struct CreateEventView:View{
    @Environment(EventStore.self) private var eventStore
    @Environment(LocationManager.self) private var locationManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var title=""
    @State private var category=""
    @State private var description=""
    @State private var placeName=""
    @State private var startsAt=Date().addingTimeInterval(30*60)
    @State private var capacity=3
    @State private var isSaving=false
    

    
    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    // タイトル、カテゴリ、説明
                    TextField("イベント名",text: $title)
                    TextField("カテゴリー",text: $category)
                    TextField("コメント",text: $description,axis: .vertical)
                }
                Section("集合") {
                    // 集合場所の名前、開始時刻、募集人数
                    DatePicker("開始時刻", selection: $startsAt,
                               in: Date().addingTimeInterval(6 * 60)...Date().addingTimeInterval(59 * 60),
                               displayedComponents: .hourAndMinute)
                    Stepper("募集人数:\(capacity)人",value: $capacity,in:1...50)
                }
            }
            .navigationTitle("イベントを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタンと作成ボタン
            }
        }
    }
}

#Preview{
    CreateEventView()
        .environment(EventStore())
        .environment(LocationManager())
}
