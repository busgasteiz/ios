import SwiftUI
import CoreLocation

// MARK: - Lista de paradas cercanas

struct NearbyStopsView: View {

    @Environment(DataManager.self) private var dataManager
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("searchRadius") private var searchRadius: Double = 200

    @State private var nearbyStops: [NearbyStop] = []
    @State private var isReloading = false

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
            radiusMenu
            reloadButton
        }
        .onChange(of: dataManager.version) { recompute() }
        .onChange(of: locationManager.locationVersion) { recompute() }
        .onAppear {
            recompute()
            if dataManager.gtfsData == nil {
                Task { await dataManager.refreshIfNeeded() }
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
                List(nearbyStops) { nearby in
                    NavigationLink {
                        StopDetailView(stop: nearby.stop, distance: nearby.distance)
                    } label: {
                        StopRowView(nearby: nearby)
                    }
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
    private var radiusMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach([100.0, 200.0, 300.0, 500.0, 1000.0], id: \.self) { r in
                    Button {
                        searchRadius = r
                        recompute()
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
                    await dataManager.forceRefresh()
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
        Task.detached(priority: .userInitiated) {
            let stops = computeNearbyStops(lat: lat, lon: lon, radius: radius, gtfsData: gtfs)
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
            StopIconView(isTram: nearby.stop.isTram)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(nearby.stop.name)
                    .font(.body)
                    .foregroundStyle(.primary)
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
