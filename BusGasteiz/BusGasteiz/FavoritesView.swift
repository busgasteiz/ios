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
        let activeStops = computeStopsWithUpcomingArrivals(gtfsData: gtfs)
        let stopRows: [(stop: StopInfo, distance: Double, hasArrivals: Bool)] = favorites.favoriteStopIds
            .compactMap { id in
                gtfs.stops[id].map { ($0, dist(for: $0), activeStops.contains(id)) }
            }
            .sorted { $0.stop.localizedName < $1.stop.localizedName }

        let routeRows: [(key: FavoritesManager.ParsedRouteKey, stop: StopInfo, color: String)] =
            favorites.parsedRouteKeys.compactMap { key in
                guard let stop = gtfs.stops[key.stopId] else { return nil }
                let color = gtfs.routes.values.first { $0.shortName == key.routeShortName }?.color ?? ""
                return (key, stop, color)
            }

        List {
            if !stopRows.isEmpty {
                Section("Stops") {
                    ForEach(stopRows, id: \.stop.id) { row in
                        NavigationLink {
                            StopDetailView(stop: row.stop, distance: row.distance)
                        } label: {
                            FavoriteStopRow(stop: row.stop, distance: row.distance, hasArrivals: row.hasArrivals)
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
                        NavigationLink {
                            RouteArrivalsView(stop: row.stop, distance: dist(for: row.stop),
                                             routeShortName: row.key.routeShortName,
                                             routeColor: row.color)
                        } label: {
                            FavoriteRouteRow(routeShortName: row.key.routeShortName,
                                            routeColor: row.color,
                                            stopName: row.stop.localizedName,
                                            isTram: row.stop.isTram)
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StopIconView(isTram: stop.isTram, size: 44, hasArrivals: hasArrivals)
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

    var body: some View {
        HStack(spacing: 12) {
            // Insignia de línea
            Text(routeShortName)
                .font(.headline)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(minWidth: 44)
                .background(Color(hex: routeColor))
                .foregroundStyle(contrastColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

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

    private var contrastColor: Color {
        let c = routeColor.lowercased()
        if c.isEmpty || c == "ffffff" { return .black }
        guard c.count == 6,
              let r = UInt8(c.prefix(2), radix: 16),
              let g = UInt8(c.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(c.dropFirst(4), radix: 16) else { return .white }
        let lum = 0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)
        return lum > 140 ? .black : .white
    }
}
