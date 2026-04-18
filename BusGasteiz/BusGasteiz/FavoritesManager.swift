import Foundation
import CoreData
import SwiftData

// MARK: - Gestión de favoritos (sincronizados con iCloud via SwiftData)

@Observable
final class FavoritesManager {

    private(set) var favoriteStopIds: Set<String> = []
    private(set) var favoriteRouteKeys: Set<String> = []  // formato: "stopId::routeShortName"

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadFromStore()
        migrateFromUserDefaultsIfNeeded()
        observeRemoteChanges()
    }

    var isEmpty: Bool { favoriteStopIds.isEmpty && favoriteRouteKeys.isEmpty }

    // MARK: Paradas

    func toggleStop(_ stopId: String) {
        if favoriteStopIds.contains(stopId) {
            favoriteStopIds.remove(stopId)
            deleteStops(matching: stopId)
        } else {
            favoriteStopIds.insert(stopId)
            modelContext.insert(FavoriteStop(stopId: stopId))
        }
        try? modelContext.save()
    }

    func isStopFavorite(_ stopId: String) -> Bool {
        favoriteStopIds.contains(stopId)
    }

    // MARK: Líneas en una parada

    func toggleRoute(stopId: String, routeShortName: String) {
        let key = routeKey(stopId: stopId, routeShortName: routeShortName)
        if favoriteRouteKeys.contains(key) {
            favoriteRouteKeys.remove(key)
            deleteRoutes(stopId: stopId, routeShortName: routeShortName)
        } else {
            favoriteRouteKeys.insert(key)
            modelContext.insert(FavoriteRoute(stopId: stopId, routeShortName: routeShortName))
        }
        try? modelContext.save()
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

    private func loadFromStore() {
        let stops = (try? modelContext.fetch(FetchDescriptor<FavoriteStop>())) ?? []
        favoriteStopIds = Set(stops.map(\.stopId))
        let routes = (try? modelContext.fetch(FetchDescriptor<FavoriteRoute>())) ?? []
        favoriteRouteKeys = Set(routes.map { routeKey(stopId: $0.stopId, routeShortName: $0.routeShortName) })
    }

    private func deleteStops(matching stopId: String) {
        let predicate = #Predicate<FavoriteStop> { $0.stopId == stopId }
        let items = (try? modelContext.fetch(FetchDescriptor<FavoriteStop>(predicate: predicate))) ?? []
        items.forEach { modelContext.delete($0) }
    }

    private func deleteRoutes(stopId: String, routeShortName: String) {
        let sId = stopId
        let rName = routeShortName
        let predicate = #Predicate<FavoriteRoute> { $0.stopId == sId && $0.routeShortName == rName }
        let items = (try? modelContext.fetch(FetchDescriptor<FavoriteRoute>(predicate: predicate))) ?? []
        items.forEach { modelContext.delete($0) }
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.loadFromStore()
        }
    }

    /// Migra los datos almacenados en UserDefaults al nuevo almacén SwiftData.
    /// Se ejecuta una sola vez; una vez migrado, no vuelve a intentarlo.
    private func migrateFromUserDefaultsIfNeeded() {
        let migratedKey = "favorites.migratedToSwiftData"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        let d = UserDefaults.standard
        let stops = d.stringArray(forKey: "favoriteStops") ?? []
        let routes = d.stringArray(forKey: "favoriteRoutes") ?? []
        if !stops.isEmpty || !routes.isEmpty {
            stops.forEach { modelContext.insert(FavoriteStop(stopId: $0)) }
            routes.forEach { key in
                let parts = key.components(separatedBy: "::")
                guard parts.count == 2 else { return }
                modelContext.insert(FavoriteRoute(stopId: parts[0], routeShortName: parts[1]))
            }
            try? modelContext.save()
            loadFromStore()
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
