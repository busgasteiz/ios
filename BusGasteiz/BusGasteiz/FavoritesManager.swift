import Foundation
import UIKit

// MARK: - Gestión de favoritos (sincronizados con iCloud Key-Value Store)

@Observable
final class FavoritesManager {

    private(set) var favoriteStopIds: Set<String> = []
    private(set) var favoriteRouteKeys: Set<String> = []  // formato: "stopId::routeShortName"

    private let store = NSUbiquitousKeyValueStore.default
    private let stopsKey = "favoriteStops"
    private let routesKey = "favoriteRoutes"

    init() {
        loadFromStore()
        migrateFromUserDefaultsIfNeeded()
        observeRemoteChanges()
        store.synchronize()
    }

    var isEmpty: Bool { favoriteStopIds.isEmpty && favoriteRouteKeys.isEmpty }

    // MARK: Paradas

    func toggleStop(_ stopId: String) {
        if favoriteStopIds.contains(stopId) {
            favoriteStopIds.remove(stopId)
        } else {
            favoriteStopIds.insert(stopId)
        }
        saveToStore()
    }

    func isStopFavorite(_ stopId: String) -> Bool {
        favoriteStopIds.contains(stopId)
    }

    // MARK: Líneas en una parada

    func toggleRoute(stopId: String, routeShortName: String) {
        let key = routeKey(stopId: stopId, routeShortName: routeShortName)
        if favoriteRouteKeys.contains(key) {
            favoriteRouteKeys.remove(key)
        } else {
            favoriteRouteKeys.insert(key)
        }
        saveToStore()
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
            // Split on the LAST "::" to correctly handle stop IDs that contain ":" (e.g. Euskotren
            // StopPlace IDs like "ES:Euskotren:StopPlace:1559:" have a trailing colon, which
            // combined with the "::" separator produces ":::". Using the last "::" gives the
            // correct stopId including the trailing colon.
            guard let range = key.range(of: "::", options: .backwards) else { return nil }
            let stopId = String(key[key.startIndex..<range.lowerBound])
            let routeShortName = String(key[range.upperBound...])
            guard !stopId.isEmpty, !routeShortName.isEmpty else { return nil }
            return ParsedRouteKey(stopId: stopId, routeShortName: routeShortName)
        }.sorted { $0.id < $1.id }
    }

    // MARK: Privado

    private func routeKey(stopId: String, routeShortName: String) -> String {
        "\(stopId)::\(routeShortName)"
    }

    private func loadFromStore() {
        let stops = store.array(forKey: stopsKey) as? [String] ?? []
        let routes = store.array(forKey: routesKey) as? [String] ?? []
        favoriteStopIds = Set(stops)
        favoriteRouteKeys = Set(routes)
    }

    private func saveToStore() {
        store.set(Array(favoriteStopIds), forKey: stopsKey)
        store.set(Array(favoriteRouteKeys), forKey: routesKey)
        store.synchronize()
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            self?.loadFromStore()
        }
    }

    private func migrateFromUserDefaultsIfNeeded() {
        let migratedKey = "favorites.migratedToiCloud"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        // Si iCloud ya tiene datos (de otro dispositivo), no sobreescribir.
        let hasCloudData = store.array(forKey: stopsKey) != nil
            || store.array(forKey: routesKey) != nil
        if !hasCloudData {
            let stops = UserDefaults.standard.stringArray(forKey: "favoriteStops") ?? []
            let routes = UserDefaults.standard.stringArray(forKey: "favoriteRoutes") ?? []
            if !stops.isEmpty || !routes.isEmpty {
                store.set(stops, forKey: stopsKey)
                store.set(routes, forKey: routesKey)
                store.synchronize()
                loadFromStore()
            }
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
