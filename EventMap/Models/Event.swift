import SwiftUI
import MapKit

// イベントのデータ型
struct Event: Identifiable, Sendable {
    let id = UUID()//
    let creatorID=UUID()//
    let organizationID=UUID()//
    let kind:String
    let title:String
    let category: String
    let description:String
    let placeName:String
    let latitude:Double
    let longitude:Double
    let scale:EventScale
    
    var coordinate:CLLocationCoordinate2D{
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// 掲載ユーザーの種類（ピンの色分けに使用）
enum EventScale: Sendable {
    case privateMode, businessMode

    var label: String {
        switch self {
        case .privateMode:  return "個人ユーザー"
        case .businessMode: return "法人ユーザー"
        }
    }

    var color: Color {
        switch self {
        case .privateMode:  return .red
        case .businessMode: return .yellow
        }
    }
}
