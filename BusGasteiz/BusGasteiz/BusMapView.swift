import SwiftUI
import MapKit

// MARK: - Mapa de paradas cercanas

struct BusMapView: View {

    @Environment(DataManager.self) private var dataManager
    @Environment(LocationManager.self) private var locationManager

    @AppStorage("searchRadius") private var searchRadius: Double = 200

    @State private var position: MapCameraPosition = .automatic
    @State private var nearbyStops: [NearbyStop] = []
    @State private var selectedStopId: String?
    @State private var selectedStop: NearbyStop?
    @State private var showStopSheet = false
    @State private var isReloading = false

    var body: some View {
        Map(position: $position, selection: $selectedStopId) {
            // Anotaciones de paradas cercanas
            ForEach(nearbyStops) { nearby in
                Annotation(nearby.stop.name, coordinate: nearby.stop.coordinate, anchor: .bottom) {
                    StopAnnotationView(isSelected: selectedStopId == nearby.stop.id)
                }
                .tag(nearby.stop.id)
            }

            // Posición del usuario
            UserAnnotation()
        }
        .mapStyle(.standard)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Mapa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { reloadButton }
        .sheet(isPresented: $showStopSheet) {
            if let nearby = selectedStop {
                NavigationStack {
                    StopDetailView(stop: nearby.stop, distance: nearby.distance)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Cerrar") { showStopSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: selectedStopId) { _, newId in
            guard let id = newId,
                  let nearby = nearbyStops.first(where: { $0.id == id }) else { return }
            selectedStop = nearby
            showStopSheet = true
        }
        .onChange(of: showStopSheet) { _, visible in
            if !visible { selectedStopId = nil }
        }
        .onChange(of: dataManager.version) { recompute() }
        .onChange(of: locationManager.locationVersion) { recompute() }
        .onAppear {
            centerOnUser()
            recompute()
        }
    }

    // MARK: Toolbar

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

    // MARK: Helpers

    private func centerOnUser() {
        if let loc = locationManager.location {
            position = .region(MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: searchRadius * 4,
                longitudinalMeters: searchRadius * 4
            ))
        }
    }

    private func recompute() {
        guard let gtfs = dataManager.gtfsData else { return }
        let lat: Double
        let lon: Double
        if let loc = locationManager.location {
            lat = loc.coordinate.latitude
            lon = loc.coordinate.longitude
        } else {
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

// MARK: - Vista de anotación en el mapa

struct StopAnnotationView: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.white)
                .frame(width: isSelected ? 28 : 22, height: isSelected ? 28 : 22)
                .shadow(radius: 3)

            Image(systemName: "bus.fill")
                .font(isSelected ? .callout : .caption2)
                .foregroundStyle(isSelected ? .white : .accentColor)
        }
        .animation(.spring(duration: 0.2), value: isSelected)
    }
}
