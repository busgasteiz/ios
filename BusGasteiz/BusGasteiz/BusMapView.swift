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
    @State private var visibleRegion: MKCoordinateRegion?

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
            MapCompass()
            MapScaleView()
        }
        .navigationTitle("Mapa")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            locationButton
            radiusMenu
            reloadButton
        }
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
        .onChange(of: searchRadius) { centerOnUser() }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            recompute()
        }
        .onAppear {
            centerOnUser()
            recompute()
            if dataManager.gtfsData == nil {
                Task { await dataManager.refreshIfNeeded() }
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var locationButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                centerOnUser()
            } label: {
                Image(systemName: "location.fill")
            }
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
        guard let gtfs = dataManager.gtfsData,
              let region = visibleRegion else { return }

        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        let minLat = region.center.latitude  - halfLat
        let maxLat = region.center.latitude  + halfLat
        let minLon = region.center.longitude - halfLon
        let maxLon = region.center.longitude + halfLon

        let refLat: Double
        let refLon: Double
        if let loc = locationManager.location {
            refLat = loc.coordinate.latitude
            refLon = loc.coordinate.longitude
        } else {
            refLat = 42.846718
            refLon = -2.671622
        }

        Task.detached(priority: .userInitiated) {
            let stops = computeStopsInBounds(
                minLat: minLat, maxLat: maxLat,
                minLon: minLon, maxLon: maxLon,
                refLat: refLat, refLon: refLon,
                gtfsData: gtfs
            )
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
