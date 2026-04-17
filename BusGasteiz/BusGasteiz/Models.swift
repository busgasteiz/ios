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
    /// - Euskera: usa nameEu si está disponible, o name (Euskotren ya está en euskera)
    /// - Castellano: usa nameEs si está disponible, o name
    /// - Otros: usa name como fallback
    var localizedName: String {
        let lang = Locale.current.language.languageCode?.identifier ?? ""
        switch lang {
        case "eu": return nameEu ?? name
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
}

/// Línea de autobús/tranvía resumida para mostrar en listas de paradas.
struct RouteTag: Sendable {
    let shortName: String
    let color: String
}

struct NearbyStop: Identifiable, Sendable {
    let stop: StopInfo
    let distance: Double
    /// Indica si la parada tiene al menos un horario en los datos GTFS.
    let hasArrivals: Bool
    /// Líneas que pasan por esta parada, ordenadas.
    let routes: [RouteTag]
    var id: String { stop.id }
}
