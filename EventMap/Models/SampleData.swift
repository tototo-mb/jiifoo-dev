import MapKit

// 仮のイベントデータ（後でサーバーなどから読み込む形に差し替え）
let sampleEvents: [Event] = [
    Event(
        kind: "法人ユーザー",
        title: "深志神社 例大祭",
        category: "参加人数無制限",
        description:"誰でも自由に参加してください！",
        placeName: "深志神社",
        latitude: 36.2298205,
        longitude: 137.9738513,
        scale: .businessMode
    ),
    
    Event(kind: "個人ユーザー",
          title: "池工祭",
          category: "文化祭",
          description: "誰でも参加してください！",
          placeName: "池田工業高校",
          latitude: 36.4136193,
          longitude: 137.8792451,
          scale: .privateMode
         )
]
