import CoreLocation
import Observation

// MARK: - LocationManager

@Observable @MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {

    var location: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Se incrementa cuando se resuelve la posición activa (al inicio o al pulsar el botón
    /// de localización). Las vistas lo observan para reaccionar al cambio de posición.
    private(set) var locationVersion: Int = 0

    /// Posición activa usada por las vistas para listar paradas y centrar el mapa.
    /// Inicializada con el centro de Vitoria-Gasteiz; solo cambia cuando el usuario
    /// pulsa el botón de localización o desplaza el mapa manualmente.
    var activePosition: CLLocation = CLLocation(
        latitude: vitoriaCenterCoordinate.latitude,
        longitude: vitoriaCenterCoordinate.longitude
    )

    /// Mensaje de aviso para el toast de localización. Se establece cuando se usa
    /// la posición predeterminada; se limpia después de mostrarse.
    var positionToastMessage: String?

    private let manager = CLLocationManager()
    private var hasResolvedInitialPosition = false

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

    /// Aplica las reglas de posición:
    /// - Sin permiso o sin fix GPS → posición predeterminada + toast
    /// - Dentro de 10 km del centro de Vitoria → posición GPS
    /// - Fuera de 10 km → posición predeterminada + toast
    ///
    /// Llama a este método al pulsar el botón de localización.
    func resolveActivePosition() {
        let defaultLoc = CLLocation(
            latitude: vitoriaCenterCoordinate.latitude,
            longitude: vitoriaCenterCoordinate.longitude
        )
        if let loc = location {
            if loc.distance(from: defaultLoc) <= vitoriaCenterRadiusMeters {
                activePosition = loc
            } else {
                activePosition = defaultLoc
                positionToastMessage = String(localized: "Outside Vitoria-Gasteiz area. Using city center.")
            }
        } else {
            activePosition = defaultLoc
            positionToastMessage = String(localized: "Location unavailable. Using Vitoria-Gasteiz city center.")
        }
        locationVersion += 1
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.location = loc
            if !self.hasResolvedInitialPosition {
                self.hasResolvedInitialPosition = true
                self.resolveActivePosition()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                if !self.hasResolvedInitialPosition {
                    self.hasResolvedInitialPosition = true
                    self.resolveActivePosition()
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // No propagamos errores de localización — la app usa coordenadas por defecto
    }
}
