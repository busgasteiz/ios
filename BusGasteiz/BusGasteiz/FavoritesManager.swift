import Foundation
import UIKit
import CoreData
import SwiftData

// MARK: - Actor privado para lecturas desde un contexto independiente

/// Usa un contexto de cola privada (vía @ModelActor) que lee directamente del almacén
/// persistente, evitando el caché del contexto principal. Necesario en Mac Catalyst
/// donde el caché del coordinador impide ver los cambios remotos de CloudKit.
@ModelActor
private actor FavoritesReader {
    func loadFavorites() throws -> (stops: [String], routes: [(String, String)]) {
        let stops = try modelContext.fetch(FetchDescriptor<FavoriteStop>())
        let routes = try modelContext.fetch(FetchDescriptor<FavoriteRoute>())
        return (
            stops.map(\.stopId),
            routes.map { ($0.stopId, $0.routeShortName) }
        )
    }
}

// MARK: - Gestión de favoritos (sincronizados con iCloud via SwiftData)

@Observable
final class FavoritesManager {

    private(set) var favoriteStopIds: Set<String> = []
    private(set) var favoriteRouteKeys: Set<String> = []  // formato: "stopId::routeShortName"

    private let modelContext: ModelContext
    private let container: ModelContainer
    private let reader: FavoritesReader
    private var pollingTimer: Timer?

    init(modelContext: ModelContext, container: ModelContainer) {
        self.modelContext = modelContext
        self.container = container
        self.reader = FavoritesReader(modelContainer: container)
        scheduleLoad()
        migrateFromUserDefaultsIfNeeded()
        observeRemoteChanges()
    }

    var isEmpty: Bool { favoriteStopIds.isEmpty && favoriteRouteKeys.isEmpty }

    // MARK: Polling en primer plano

    func startForegroundPolling() {
        guard pollingTimer == nil else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.scheduleLoad()
        }
    }

    func stopForegroundPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

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

    /// Lanza una tarea asíncrona que lee desde el actor privado de cola privada
    /// y actualiza el estado observable en el hilo principal.
    private func scheduleLoad() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let result = try? await self.reader.loadFavorites() else { return }
            self.favoriteStopIds = Set(result.stops)
            self.favoriteRouteKeys = Set(result.routes.map {
                self.routeKey(stopId: $0.0, routeShortName: $0.1)
            })
        }
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
        // NSPersistentStoreRemoteChange: el PSC lo publica al escribir cualquier cambio remoto.
        // Es la señal más fiable en Mac Catalyst (antes de que el contexto principal fusione).
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleLoad()
        }
        // Notificación de CloudKit: se dispara al terminar cada importación exitosa.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                event.succeeded
            else { return }
            self?.scheduleLoad()
        }
        // Respaldo: cambios llegados mientras la app estaba suspendida.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleLoad()
        }
    }

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
            scheduleLoad()
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    }
}
