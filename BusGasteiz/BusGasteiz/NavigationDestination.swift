import Foundation

// MARK: - Destinos de navegación compartidos entre pestañas

enum AppNavDestination: Hashable {
    case stopDetail(stop: StopInfo, distance: Double, starLeading: Bool = false)
    case routeArrivals(stop: StopInfo, distance: Double, routeShortName: String, routeColor: String)
}
