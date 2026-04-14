import Foundation

// MARK: - Gestión de favoritos

@Observable
final class FavoritesManager {

    private(set) var favoriteStopIds: Set<String>
    private(set) var favoriteRouteKeys: Set<String>  // formato: "stopId::routeShortName"

    private let stopsKey  = "favoriteStops"
    private let routesKey = "favoriteRoutes"

    init() {
        let d = UserDefaults.standard
        favoriteStopIds   = Set(d.stringArray(forKey: "favoriteStops")  ?? [])
        favoriteRouteKeys = Set(d.stringArray(forKey: "favoriteRoutes") ?? [])
    }

    var isEmpty: Bool { favoriteStopIds.isEmpty && favoriteRouteKeys.isEmpty }

    // MARK: Paradas

    func toggleStop(_ stopId: String) {
        if favoriteStopIds.contains(stopId) { favoriteStopIds.remove(stopId) }
        else { favoriteStopIds.insert(stopId) }
        save()
    }

    func isStopFavorite(_ stopId: String) -> Bool {
        favoriteStopIds.contains(stopId)
    }

    // MARK: Líneas en una parada

    func toggleRoute(stopId: String, routeShortName: String) {
        let key = routeKey(stopId: stopId, routeShortName: routeShortName)
        if favoriteRouteKeys.contains(key) { favoriteRouteKeys.remove(key) }
        else { favoriteRouteKeys.insert(key) }
        save()
    }

    func isRouteFavorite(stopId: String, routeShortName: String) -> Bool {
        favoriteRouteKeys.contains(routeKey(stopId: stopId, routeShortName: routeShortName))
    }

    // MARK: Claves de rutas parseadas

    struct ParsedRouteKey: Identifiable {
        let stopId: String
        let routeShortName: String
        var id: String { "\(stopId)::\(routeShortName)" }
    }

    var parsedRouteKeys: [ParsedRouteKey] {
        favoriteRouteKeys.compactMap { key in
            let parts = key.components(separatedBy: "::")
            guard parts.count == 2 else { return nil }
            return ParsedRouteKey(stopId: parts[0], routeShortName: parts[1])
        }.sorted { $0.id < $1.id }
    }

    // MARK: Privado

    private func routeKey(stopId: String, routeShortName: String) -> String {
        "\(stopId)::\(routeShortName)"
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(Array(favoriteStopIds),   forKey: stopsKey)
        d.set(Array(favoriteRouteKeys), forKey: routesKey)
    }
}
