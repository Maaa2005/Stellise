import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    private let manager = CLLocationManager()
    
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus
    
    // 待機用 (Errorを投げる可能性があるため、Error型を指定)
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Error>?

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced // 都市レベルの精度
    }

    /// 位置情報をリクエストする（許可がなければポップアップを出す）
    func requestLocation() async throws -> CLLocationCoordinate2D? {
        // 1. 権限状態を確認
        if manager.authorizationStatus == .notDetermined {
            print("📍 権限が未定のため、ポップアップを表示します")
            manager.requestWhenInUseAuthorization()
        }
        
        // 2. 既に拒否されている場合
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            print("📍 位置情報が拒否されています")
            return nil
        }
        
        // 3. 位置情報取得を開始
        // ★修正箇所: withCheckedThrowingContinuation を使用します
        return try await withCheckedThrowingContinuation { continuation in
            
            // 既にタスクがある場合はキャンセルして新しいのを優先
            if self.locationContinuation != nil {
                self.locationContinuation?.resume(throwing: CLError(.locationUnknown))
            }
            
            // コンティニュエーションを保持
            self.locationContinuation = continuation
            
            // 権限があるならすぐに取得開始、なければ権限変更を待つ
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    // 権限が変わった時に呼ばれる
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        print("📍 権限状態変更: \(authorizationStatus.rawValue)")
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        } else if authorizationStatus == .denied || authorizationStatus == .restricted {
            // 拒否された場合はエラーとして再開させる
            locationContinuation?.resume(throwing: CLError(.denied))
            locationContinuation = nil
        }
    }

    // 位置取得成功
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        print("📍 位置取得成功: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
        self.lastKnownLocation = loc.coordinate
        
        locationContinuation?.resume(returning: loc.coordinate)
        locationContinuation = nil
    }

    // エラー
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 位置取得エラー: \(error.localizedDescription)")
        
        // 未決定の場合はエラーにせず無視（ポップアップ中の可能性があるため）
        if manager.authorizationStatus == .notDetermined { return }
        
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}
