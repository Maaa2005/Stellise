import Foundation
import MapKit
import CoreLocation

class MapKitHelper {
    
    static func calculateTravelTime(from origin: CLLocationCoordinate2D, to address: String, mode: String) async -> Int? {
        let geocoder = CLGeocoder()
        
        // 住所から座標へ変換
        guard let destPlacemarks = try? await geocoder.geocodeAddressString(address),
              let destLoc = destPlacemarks.first?.location else {
            return nil
        }
        
        // ルート計算リクエスト作成
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destLoc.coordinate))
        
        // 移動手段の変換
        switch mode {
        case "walking": request.transportType = .walking
        case "transit": request.transportType = .transit
        default:        request.transportType = .automobile
        }
        
        let directions = MKDirections(request: request)

        do {
            // MapKitのルート計算(calculate)は電車(.transit)非対応。
            // 電車はETA専用API(calculateETA)でのみ所要時間が取れる。
            if request.transportType == .transit {
                let eta = try await directions.calculateETA()
                debugLog("🍎 MapKit ETA計算成功(電車): \(Int(eta.expectedTravelTime / 60))分")
                return Int(eta.expectedTravelTime)
            }
            let response = try await directions.calculate()
            if let route = response.routes.first {
                debugLog("🍎 MapKit計算成功: \(Int(route.expectedTravelTime / 60))分")
                return Int(route.expectedTravelTime)
            }
        } catch {
            debugLog("❌ MapKit Error: \(error.localizedDescription)")
        }
        return nil
    }
}
