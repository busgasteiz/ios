import SwiftData
import Foundation

// MARK: - Modelos SwiftData para favoritos (sincronizados con iCloud)

/// CloudKit requiere que todas las propiedades tengan valor por defecto.
/// No se usan restricciones @Attribute(.unique) porque CloudKit no las admite;
/// la unicidad se garantiza a nivel de FavoritesManager.

@Model
final class FavoriteStop {
    var stopId: String = ""
    var addedAt: Date = Date()

    init(stopId: String) {
        self.stopId = stopId
        self.addedAt = Date()
    }
}

@Model
final class FavoriteRoute {
    var stopId: String = ""
    var routeShortName: String = ""
    var addedAt: Date = Date()

    init(stopId: String, routeShortName: String) {
        self.stopId = stopId
        self.routeShortName = routeShortName
        self.addedAt = Date()
    }
}
