import SwiftUI
import CoreLocation

// MARK: - Lista de paradas cercanas

struct NearbyStopsView: View {

    @Environment(DataManager.self) private var dataManager
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("searchRadius") private var searchRadius: Double = 200

    @State private var nearbyStops: [NearbyStop] = []
    @State private var recomputeTask: Task<Void, Never>?
    @State private var isReloading = false
    @State private var isLocating = false
    @State private var showingAbout = false

    var body: some View {
        Group {
            switch dataManager.loadState {
            case .idle:
                loadingView(message: String(localized: "Starting up…"))

            case .loading(let msg):
                loadingView(message: msg)

            case .failed(let msg):
                errorView(message: msg)

            case .ready:
                stopsListView
            }
        }
        .navigationTitle("Nearby Stops")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            locationButton
            radiusMenu
            reloadButton
        }
        .onChange(of: dataManager.version) { recompute() }
        .onChange(of: locationManager.locationVersion) { recompute() }
        .onChange(of: searchRadius) { recompute() }
        .onAppear {
            recompute()
            if dataManager.gtfsData == nil {
                Task { await dataManager.refreshIfNeeded() }
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

    private var stopsListView: some View {
        Group {
            if nearbyStops.isEmpty {
                ContentUnavailableView(
                    "No Nearby Stops",
                    systemImage: "bus.doubledecker",
                    description: Text("There are no stops within \(Int(searchRadius)) m.\nIncrease the search radius.")
                )
            } else {
                List {
                    ForEach(nearbyStops) { nearby in
                        NavigationLink(value: AppNavDestination.stopDetail(
                            stop: nearby.stop, distance: nearby.distance)) {
                            StopRowView(nearby: nearby)
                        }
                    }

                    Button {
                        showingAbout = true
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 22))
                            Text("About BusGasteiz")
                                .font(.caption)
                        }
                        .foregroundStyle(.accent.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderless)
                    .listRowSeparator(.hidden, edges: .bottom)
                }
                .listStyle(.plain)
                .refreshable {
                    // Ejecutar refresco y espera mínima en paralelo para que
                    // la animación de carga sea siempre visible al menos 1 segundo.
                    async let refresh: () = dataManager.forceRefresh()
                    async let minDelay: () = Task.sleep(for: .seconds(1))
                    _ = await (refresh, try? minDelay)
                    recompute()
                }
                .sheet(isPresented: $showingAbout) {
                    AboutView()
                }
            }
        }
    }

    private func loadingView(message: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label("Error Loading Data", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task { await dataManager.forceRefresh() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var locationButton: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarTrailing) {
                locationButtonContent
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                locationButtonContent
            }
        }
    }

    @ViewBuilder
    private var locationButtonContent: some View {
        Button {
            Task {
                isLocating = true
                async let minDelay: () = Task.sleep(for: .seconds(1))
                recompute()
                _ = try? await minDelay
                isLocating = false
            }
        } label: {
            if isLocating {
                ProgressView()
            } else {
                Image(systemName: "location.fill")
            }
        }
        .disabled(isLocating)
    }

    @ToolbarContentBuilder
    private var radiusMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach([100.0, 200.0, 300.0, 500.0, 1000.0], id: \.self) { r in
                    Button {
                        searchRadius = r
                    } label: {
                        if r == searchRadius {
                            Label("\(Int(r)) m", systemImage: "checkmark")
                        } else {
                            Text("\(Int(r)) m")
                        }
                    }
                }
            } label: {
                Text("\(Int(searchRadius)) m")
            }
        }
    }

    @ToolbarContentBuilder
    private var reloadButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task {
                    isReloading = true
                    async let refresh: () = dataManager.forceRefresh()
                    async let minDelay: () = Task.sleep(for: .seconds(1))
                    _ = await (refresh, try? minDelay)
                    recompute()
                    isReloading = false
                }
            } label: {
                if isReloading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(isReloading)
        }
    }

    // MARK: Cálculo

    private func recompute() {
        guard let gtfs = dataManager.gtfsData else { return }
        let lat: Double
        let lon: Double
        if let loc = locationManager.location {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
        } else {
            // Coordenadas por defecto: centro de Vitoria-Gasteiz
            lat = 42.846718
            lon = -2.671622
        }
        let radius = searchRadius
        let activeIds = dataManager.activeStopIds
        recomputeTask?.cancel()
        recomputeTask = Task.detached(priority: .userInitiated) {
            let stops = computeNearbyStops(lat: lat, lon: lon, radius: radius, gtfsData: gtfs, activeStopIds: activeIds)
            guard !Task.isCancelled else { return }
            await MainActor.run { nearbyStops = stops }
        }
    }
}

// MARK: - Fila de parada

struct StopRowView: View {
    let nearby: NearbyStop
    @Environment(FavoritesManager.self) private var favorites

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            StopIconView(isTram: nearby.stop.isTram, size: 44, hasArrivals: nearby.hasArrivals)
                .frame(width: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(nearby.stop.localizedName)
                    .font(.body)
                    .foregroundStyle(.primary)
                if !nearby.routes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(nearby.routes, id: \.shortName) { route in
                            RouteBadgeView(routeShortName: route.shortName,
                                          colorHex: route.color,
                                          outerSize: 28)
                        }
                    }
                    .padding(.vertical, 2)
                }
                Text(distanceLabel(nearby.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                favorites.toggleStop(nearby.stop.id)
            } label: {
                Image(systemName: favorites.isStopFavorite(nearby.stop.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.isStopFavorite(nearby.stop.id) ? .yellow : .secondary)
                    .animation(.spring(duration: 0.2), value: favorites.isStopFavorite(nearby.stop.id))
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func distanceLabel(_ d: Double) -> String {
        d < 1000
            ? String(format: String(localized: "%lld m"), Int(d.rounded()))
            : String(format: "%.1f km", d / 1000)
    }
}
