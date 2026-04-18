import Foundation
import Observation

// MARK: - Configuración compartida de la app

/// Fuente de verdad única para los ajustes que comparten varias vistas.
/// Se inyecta como objeto de entorno desde BusGasteizApp y se persiste
/// manualmente en UserDefaults para evitar las inconsistencias de
/// sincronización que tiene @AppStorage entre distintas vistas.
@Observable final class AppSettings {

    // MARK: Valores persistidos

    var searchRadius: Double {
        didSet { UserDefaults.standard.set(searchRadius, forKey: Keys.searchRadius) }
    }

    // MARK: Claves UserDefaults

    private enum Keys {
        static let searchRadius = "searchRadius"
    }

    // MARK: Init

    init() {
        let stored = UserDefaults.standard.double(forKey: Keys.searchRadius)
        searchRadius = stored > 0 ? stored : 200
    }
}
