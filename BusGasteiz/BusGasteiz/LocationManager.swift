import CoreLocation
import Observation

// MARK: - LocationManager

@Observable @MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {

    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Se incrementa con cada actualización de posición; útil para `onChange` en vistas.
    private(set) var locationVersion: Int = 0

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50  // actualizar cada 50 m
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermissionIfNeeded() {
        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            self.locationVersion += 1
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // No propagamos errores de localización — la app usa coordenadas por defecto
    }
}
