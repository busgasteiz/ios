import Foundation
import CoreLocation

// MARK: - GTFS estático

struct StopInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
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

struct NearbyStop: Identifiable, Sendable {
    let stop: StopInfo
    let distance: Double
    var id: String { stop.id }
}
