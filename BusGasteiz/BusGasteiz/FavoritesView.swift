import SwiftUI
import CoreLocation

// MARK: - Pestaña de favoritos

struct FavoritesView: View {

    @Environment(DataManager.self)      private var dataManager
    @Environment(LocationManager.self)  private var locationManager
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        Group {
            if favorites.isEmpty {
                emptyView
            } else if let gtfs = dataManager.gtfsData {
                favoritesList(gtfs: gtfs)
            } else {
                loadingView
            }
        }
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await dataManager.forceRefresh() }
                } label: {
                    if dataManager.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(dataManager.isRefreshing)
            }
        }
        .navigationDestination(for: AppNavDestination.self) { dest in
            switch dest {
            case .stopDetail(let stop, let distance, let starLeading):
                StopDetailView(stop: stop, distance: distance, starLeading: starLeading)
            case .routeArrivals(let stop, let distance, let routeShortName, let routeColor):
                RouteArrivalsView(stop: stop, distance: distance,
                                  routeShortName: routeShortName, routeColor: routeColor)
            }
        }
    }

    // MARK: Subvistas

    private var emptyView: some View {
        ContentUnavailableView(
            "No Favorites",
            systemImage: "star",
            description: Text("Tap the star on a stop or line to save it here.")
        )
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.5)
            Text("Loading data…").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func favoritesList(gtfs: GTFSData) -> some View {
        // Construye las listas de favoritos resueltos contra el GTFS
        let activeStops = dataManager.activeStopIds
        let alerts = dataManager.serviceAlerts
        let stopRows: [(stop: StopInfo, distance: Double, hasArrivals: Bool, hasAlert: Bool)] = favorites.favoriteStopIds
            .compactMap { id in
                gtfs.stops[id].map { ($0, dist(for: $0), activeStops.contains(id), alerts.stopIds.contains(id)) }
            }
            .sorted { $0.stop.localizedName < $1.stop.localizedName }

        let routeRows: [(key: FavoritesManager.ParsedRouteKey, stop: StopInfo, color: String, hasAlert: Bool)] =
            favorites.parsedRouteKeys.compactMap { key in
                guard let stop = gtfs.stops[key.stopId] else { return nil }
                let route = gtfs.routes.values.first(where: { $0.shortName == key.routeShortName })
                    ?? gtfs.routes.values.first(where: { $0.shortName == String(key.routeShortName.prefix(while: { $0.isNumber })) })
                let color = route?.color ?? ""
                let hasAlert = route.map { alerts.routeIds.contains($0.id) } ?? false
                return (key, stop, color, hasAlert)
            }

        List {
            if !stopRows.isEmpty {
                Section("Stops") {
                    ForEach(stopRows, id: \.stop.id) { row in
                        NavigationLink(value: AppNavDestination.stopDetail(
                            stop: row.stop, distance: row.distance)) {
                            FavoriteStopRow(stop: row.stop, distance: row.distance,
                                           hasArrivals: row.hasArrivals, hasAlert: row.hasAlert)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                favorites.toggleStop(row.stop.id)
                            } label: {
                                Label("Remove from Favorites", systemImage: "star.slash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet { favorites.toggleStop(stopRows[idx].stop.id) }
                    }
                }
            }

            if !routeRows.isEmpty {
                Section("Lines") {
                    ForEach(routeRows, id: \.key.id) { row in
                        NavigationLink(value: AppNavDestination.routeArrivals(
                            stop: row.stop, distance: dist(for: row.stop),
                            routeShortName: row.key.routeShortName,
                            routeColor: row.color)) {
                            FavoriteRouteRow(routeShortName: row.key.routeShortName,
                                            routeColor: row.color,
                                            stopName: row.stop.localizedName,
                                            isTram: row.stop.isTram,
                                            hasAlert: row.hasAlert)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                favorites.toggleRoute(stopId: row.key.stopId,
                                                      routeShortName: row.key.routeShortName)
                            } label: {
                                Label("Remove from Favorites", systemImage: "star.slash")
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let key = routeRows[idx].key
                            favorites.toggleRoute(stopId: key.stopId, routeShortName: key.routeShortName)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            async let refresh: () = dataManager.forceRefresh()
            async let minDelay: () = Task.sleep(for: .seconds(1))
            _ = await (refresh, try? minDelay)
        }
    }

    private func dist(for stop: StopInfo) -> Double {
        guard let loc = locationManager.location else { return 0 }
        return CLLocation(latitude: stop.lat, longitude: stop.lon).distance(from: loc)
    }
}

// MARK: - Fila de parada favorita

struct FavoriteStopRow: View {
    let stop: StopInfo
    let distance: Double
    var hasArrivals: Bool = true
    var hasAlert: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StopIconView(isTram: stop.isTram, size: 44, hasArrivals: hasArrivals, hasAlert: hasAlert)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.localizedName)
                    .font(.body)
                Text(distanceLabel(distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func distanceLabel(_ d: Double) -> String {
        if d == 0 { return String(localized: "Favorite stop") }
        return d < 1000
            ? String(format: String(localized: "%lld m"), Int(d.rounded()))
            : String(format: "%.1f km", d / 1000)
    }
}

// MARK: - Fila de línea-en-parada favorita

struct FavoriteRouteRow: View {
    let routeShortName: String
    let routeColor: String
    let stopName: String
    let isTram: Bool
    var hasAlert: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Badge de línea cuadrado
            RouteBadgeView(routeShortName: routeShortName, colorHex: routeColor, hasAlert: hasAlert)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(stopName)
                    .font(.body)
                Text(isTram ? String(localized: "Tram") : String(localized: "Bus"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
