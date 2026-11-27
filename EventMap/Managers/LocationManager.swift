import CoreLocation
import Observation

// 位置情報マネージャー
@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()

    var userLocation: CLLocationCoordinate2D?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy   // 「正確な位置情報」がオンか
    var isServicesEnabled = true
    
    override init() {
        super.init()
        manager.delegate = self   // 設定直後に didChangeAuthorization が呼ばれる
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10   // 10m 以上動いたときだけ更新
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            self.accuracyAuthorization = accuracy
            self.handleAuthorization(status)
            await self.refreshServicesEnabled()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            self.userLocation = coordinate
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("位置情報の取得に失敗しました:\(error.localizedDescription)")
    }

    // MARK: - 内部処理

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break   // denied / restricted
        }
    }

    // 現在地からの距離（メートル）。現在地がまだ分からないときは nil
    func distance(to coordinate: CLLocationCoordinate2D) -> CLLocationDistance? {
        guard let userLocation else { return nil }
        let from = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
        let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return from.distance(from: to)
    }
    
    static let joinableRadius:CLLocationDistance=800
    
    func isJoinable(_ coordinate:CLLocationCoordinate2D) -> Bool{
        guard let distance=distance(to: coordinate) else { return false }
        return distance <= Self.joinableRadius
    }

    // iPhone 全体の位置情報サービスがオンか調べ直す
    // (メインスレッドで調べると画面が固まることがあるので、裏で調べる)
    func refreshServicesEnabled() async {
        isServicesEnabled = await Task.detached {
            CLLocationManager.locationServicesEnabled()
        }.value
    }

    // 位置情報が使えない理由(問題なし・まだ聞いていないときは nil)
    var permissionProblem: LocationPermissionProblem? {
        switch authorizationStatus {
        case .notDetermined:
            return nil
        case .restricted:
            return .restricted
        case .denied:
            return isServicesEnabled ? .denied : .servicesOff
        case .authorizedAlways, .authorizedWhenInUse:
            return accuracyAuthorization == .reducedAccuracy ? .reducedAccuracy : nil
        @unknown default:
            return nil
        }
    }
}

// 距離を「450m」「1.2km」の形に変換
func formatDistance(_ meters: CLLocationDistance) -> String {
    if meters < 1000 {
        return "\(Int(meters))m"
    } else {
        return String(format: "%.1fkm", meters / 1000)
    }
}
