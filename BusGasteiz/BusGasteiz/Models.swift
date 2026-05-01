import Foundation
import CoreLocation

// MARK: - GTFS estático

struct StopInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String          // Nombre base del GTFS (castellano en Tuvisa, euskera en Euskotren)
    var nameEu: String? = nil // Nombre en euskera de translations.txt (solo Tuvisa)
    var nameEs: String? = nil // Nombre en castellano de translations.txt (solo Tuvisa)
    let lat: Double
    let lon: Double
    var isTram: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Nombre adaptado al idioma del sistema.
    /// - Euskera: usa nameEu si está disponible, o name (Euskotren ya está en euskera).
    ///   Si el nombre en euskera no contiene ningún número pero el nombre en castellano
    ///   termina en un número de portal, se le añade al final para mantener consistencia
    ///   (Tuvisa omite los números de portal en las traducciones al euskera).
    /// - Castellano: usa nameEs si está disponible, o name
    /// - Otros: usa name como fallback
    var localizedName: String {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        switch lang {
        case "eu":
            guard let eu = nameEu else { return name }
            if !eu.contains(where: \.isNumber) {
                let ref = nameEs ?? name
                if let range = ref.range(of: #"\s+\d+$"#, options: .regularExpression) {
                    return eu + String(ref[range])
                }
            }
            return eu
        case "es": return nameEs ?? name
        default:   return name
        }
    }
}

struct TripInfo: Sendable {
    let id: String
    let routeId: String
    let headsign: String
    let serviceId: String
}

struct RouteInfo: Sendable {
    let id: String
    let shortName: String
    let longName: String
    let color: String
}

struct StopTimeEntry: Sendable {
    let tripId: String
    let stopSequence: Int
    let arrivalSecs: Int
}

// MARK: - Tiempo real

struct TripDelayInfo: Sendable {
    var generalDelay: Int32 = 0
    var stopDelays: [String: Int32] = [:]
    var vehicleLabel: String = ""
    nonisolated init() {}
}

// MARK: - Alertas de servicio (GTFS-RT Alerts)

struct ServiceAlert: Identifiable, Sendable {
    let id = UUID()
    let headerText: String
    let descriptionText: String
    /// GTFS-RT cause enum (0 = no especificado, 1 = UNKNOWN_CAUSE, 5 = DEMONSTRATION, …)
    var cause: Int = 0
    /// GTFS-RT effect enum (0 = no especificado, 1 = NO_SERVICE, 3 = SIGNIFICANT_DELAYS, …)
    var effect: Int = 0

    var causeText: String? {
        switch cause {
        case 2:  return String(localized: "Other cause")
        case 3:  return String(localized: "Technical problem")
        case 4:  return String(localized: "Strike")
        case 5:  return String(localized: "Demonstration")
        case 6:  return String(localized: "Accident")
        case 7:  return String(localized: "Holiday")
        case 8:  return String(localized: "Weather")
        case 9:  return String(localized: "Maintenance")
        case 10: return String(localized: "Construction")
        case 11: return String(localized: "Police activity")
        case 12: return String(localized: "Medical emergency")
        default: return nil
        }
    }

    var effectText: String? {
        switch effect {
        case 1:  return String(localized: "No service")
        case 2:  return String(localized: "Reduced service")
        case 3:  return String(localized: "Significant delays")
        case 4:  return String(localized: "Detour")
        case 5:  return String(localized: "Additional service")
        case 6:  return String(localized: "Modified service")
        case 9:  return String(localized: "Stop moved")
        case 11: return String(localized: "Accessibility issue")
        default: return nil
        }
    }
}

struct ServiceAlerts: Sendable {
    var stopAlerts: [String: [ServiceAlert]] = [:]    // stop_id  → alertas
    var routeAlerts: [String: [ServiceAlert]] = [:]   // route_id → alertas
    var stopIds:  Set<String> = []
    var routeIds: Set<String> = []
    var isEmpty: Bool { stopAlerts.isEmpty && routeAlerts.isEmpty }
    nonisolated init() {}
}

// MARK: - Datos GTFS agregados

struct GTFSData: Sendable {
    var stops: [String: StopInfo] = [:]
    var trips: [String: TripInfo] = [:]
    var routes: [String: RouteInfo] = [:]
    /// stop_id → lista de horarios
    var stopArrivals: [String: [StopTimeEntry]] = [:]
    /// date (yyyyMMdd) → Set<service_id>
    var activeDates: [String: Set<String>] = [:]
    nonisolated init() {}
}

// MARK: - Resultados de consulta

struct UpcomingArrival: Identifiable, Sendable {
    let id = UUID()
    let stopId: String
    let stopName: String
    let distanceMeters: Double
    let routeShortName: String
    let routeLongName: String
    let routeColor: String
    let headsign: String
    let scheduledTime: Date
    let predictedTime: Date
    let delaySecs: Int32
    let vehicleLabel: String
    let isRealTime: Bool
    var hasAlert: Bool = false
}

/// Línea de autobús/tranvía resumida para mostrar en listas de paradas.
struct RouteTag: Sendable {
    let shortName: String
    let color: String
    var hasAlert: Bool = false
}

struct NearbyStop: Identifiable, Sendable {
    let stop: StopInfo
    let distance: Double
    /// Indica si la parada tiene al menos un horario en los datos GTFS.
    let hasArrivals: Bool
    /// Líneas que pasan por esta parada, ordenadas.
    let routes: [RouteTag]
    var hasAlert: Bool = false
    var id: String { stop.id }
}
