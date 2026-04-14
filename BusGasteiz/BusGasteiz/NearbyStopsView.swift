import SwiftUI
import CoreLocation

// MARK: - Lista de paradas cercanas

struct NearbyStopsView: View {

    @Environment(DataManager.self) private var dataManager
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("searchRadius") private var searchRadius: Double = 200

    @State private var nearbyStops: [NearbyStop] = []
    @State private var isRefreshing = false

    var body: some View {
        Group {
            switch dataManager.loadState {
            case .idle:
                loadingView(message: "Iniciando…")

            case .loading(let msg):
                loadingView(message: msg)

            case .failed(let msg):
                errorView(message: msg)

            case .ready:
                stopsListView
            }
        }
        .navigationTitle("Paradas cercanas")
        .navigationBarTitleDisplayMode(.large)
        .toolbar { radiusMenu }
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
                    "Sin paradas cercanas",
                    systemImage: "bus.doubledecker",
                    description: Text("No hay paradas en un radio de \(Int(searchRadius)) m.\nAumenta el radio de búsqueda.")
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
                    isRefreshing = true
                    await dataManager.forceRefresh()
                    recompute()
                    isRefreshing = false
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
            Label("Error al cargar datos", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Reintentar") {
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
                Label("\(Int(searchRadius)) m", systemImage: "scope")
            }
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bus.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(nearby.stop.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(distanceLabel(nearby.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func distanceLabel(_ d: Double) -> String {
        d < 1000 ? "\(Int(d.rounded())) m" : String(format: "%.1f km", d / 1000)
    }
}
