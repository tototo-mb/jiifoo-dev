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
    @State private var hasCapacityLimit=true
    

    
    var body: some View {
        NavigationStack {
            Form {
                Section("イベント") {
                    // タイトル、カテゴリ、説明
                    TextField("イベント名",text: $title)
                    //TextField("カテゴリー",text: $category)
                    TextField("コメント",text: $description,axis: .vertical)
                }
                Section("集合") {
                    // 集合場所の名前、開始時刻、募集人数
                    TextField("集合場所（例：渋谷駅　ハチ公前）",text: $placeName)
                    DatePicker("開始時刻", selection: $startsAt,
                               in: Date().addingTimeInterval(6 * 60)...Date().addingTimeInterval(59 * 60),
                               displayedComponents: [.date,.hourAndMinute])
                    Toggle("募集人数に上限を設ける",isOn: $hasCapacityLimit)
                    if hasCapacityLimit{
                        Picker("募集人数",selection: $capacity){
                            ForEach(1...10,id:\.self){n in
                                Text("\(n)人").tag(n)
                            }
                        }
                    }
                }
            }
            .navigationTitle("イベントを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // キャンセルボタンと作成ボタン
                ToolbarItem(placement: .cancellationAction){
                    Button("キャンセル"){ dismiss()}
                }
                ToolbarItem(placement:.confirmationAction){
                    Button("作成"){ save() }
                        .disabled(title.isEmpty || placeName.isEmpty || isSaving )
                }
            }
            .alert(eventStore.message ?? "", isPresented:Binding(
                get:{eventStore.message != nil},
                set:{if !$0{ eventStore.message = nil}}
            )){
                Button("OK",role: .cancel){}
            }
        }
    }
    private func save() {
        // ① 現在地を取り出す。取れていなければ何もしない
        guard let coordinate = locationManager.userLocation else { return }

        Task {
            isSaving=true

            // ③ イベントを作る
            let success = await eventStore.create(
                title: title,
                category: "other",
                description: description,
                placeName: placeName,
                coordinate: coordinate,
                startsAt: startsAt,
                /* 上限ありなら capacity、なしなら nil */
                capacity: hasCapacityLimit ? capacity : nil
                    
            )

            // ④ 保存中を解除する
            isSaving = false

            // ⑤ 成功したら画面を閉じる
            if success{
                dismiss()
            }

        }
    }
}


#Preview{
    CreateEventView()
        .environment(EventStore())
        .environment(LocationManager())
}
